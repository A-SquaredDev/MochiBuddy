//
//  WidgetStateTests.swift
//  MochiBuddyTests
//
//  The App Group contract: the app owns all writes, the widget only
//  reads, and the widget's evaluation (stored baseline + live buffer)
//  must equal the engine's answer for the same instant - the widget is
//  another consumer of the one curve.
//
//  Dates.now anchor: Wed 8 Jul 2026, 10:00 local.
//

import Foundation
import Testing
@testable import MochiBuddy

private func makeState(
    displayState: MochiWidgetState.DisplayState = .active,
    baseline: [MochiWidgetState.ForecastPoint] = [],
    nextTasks: [MochiWidgetState.NextTask] = [],
    hideTaskNames: Bool = false,
    vacationEnd: Date? = nil
) -> MochiWidgetState {
    MochiWidgetState(
        displayState: displayState,
        themeId: "sesame",
        baseline: baseline,
        hideTaskNames: hideTaskNames,
        nextTasks: nextTasks,
        vacationEnd: vacationEnd,
        lastComputed: Dates.now
    )
}

@Suite("MochiWidgetState · evaluation")
struct WidgetStateEvaluationTests {

    @Test("the locked state-variant table: Complete everywhere, Pet only while active")
    func displayStateRules() {
        for state in [MochiWidgetState.DisplayState.active, .lapsed, .vacation] {
            #expect(state.allowsComplete,
                    "\(state): completing from the widget stays available in every state")
        }
        #expect(MochiWidgetState.DisplayState.active.allowsPet)
        #expect(!MochiWidgetState.DisplayState.lapsed.allowsPet, "Mochi's napping")
        #expect(!MochiWidgetState.DisplayState.vacation.allowsPet, "Mochi's resting")
    }

    @Test("baseline interpolates linearly between samples and clamps at the ends")
    func baselineLerp() {
        let state = makeState(baseline: [
            .init(date: Dates.now, value: 58),
            .init(date: Dates.hours(1), value: 40),
            .init(date: Dates.hours(2), value: 40),
        ])
        #expect(state.baselineValue(at: Dates.hours(-1)) == 58, "before the curve: first sample")
        #expect(state.baselineValue(at: Dates.now) == 58)
        #expect(abs(state.baselineValue(at: Dates.hours(0.5)) - 49) < 0.001, "midpoint lerps")
        #expect(state.baselineValue(at: Dates.hours(5)) == 40, "past the curve: last sample")
    }

    @Test("displayed adds the live buffer with the same decay and cap as everywhere else")
    func displayedAddsBuffer() {
        let state = makeState(baseline: [.init(date: Dates.now, value: 50)])
        let boost = BufferBoost(lift: 20, startedAt: Dates.now, duration: 2 * 3600)

        #expect(state.displayedValue(at: Dates.now, boosts: [boost]) == 70)
        #expect(state.displayedValue(at: Dates.hours(1), boosts: [boost]) == 60, "linear decay")
        let stacked = [boost, BufferBoost(lift: 25, startedAt: Dates.now, duration: 2 * 3600)]
        #expect(state.displayedValue(at: Dates.now, boosts: stacked) == 50 + MochiComfort.bufferCap,
                "the +30 cap holds on the widget too")
    }

    @Test("mood changes land at band boundaries, on the new side, deduped when face and label share one")
    func visibleMoodChanges() {
        // 58 → 20 over one hour: crosses 50 (label AND face - one change),
        // then 35 (label only), then 25 (face only). Flat afterwards.
        let state = makeState(baseline: [
            .init(date: Dates.now, value: 58),
            .init(date: Dates.hours(1), value: 20),
            .init(date: Dates.hours(12), value: 20),
        ])
        let changes = state.visibleMoodChanges(from: Dates.now, until: Dates.hours(12), boosts: [])

        #expect(changes.count == 3)
        let exact: [TimeInterval] = [8.0 / 38 * 3600, 23.0 / 38 * 3600, 33.0 / 38 * 3600]
        for (change, offset) in zip(changes, exact) {
            #expect(abs(change.timeIntervalSince(Dates.now) - offset) <= 60,
                    "each change is located to within the minute")
        }
        // Each returned instant already renders the NEW mood.
        #expect(MoodBand(value: state.displayedValue(at: changes[0], boosts: [])) == .uneasy)
        #expect(MoodBand(value: state.displayedValue(at: changes[1], boosts: [])) == .anxious)
        #expect(MochiMood(vitality: state.displayedValue(at: changes[2], boosts: [])) == .unwell)
    }

    @Test("a fading boost alone schedules a change - the face drops when the lift runs out")
    func boostDecayChange() {
        let state = makeState(baseline: [.init(date: Dates.now, value: 48)])
        let boost = BufferBoost(lift: 10, startedAt: Dates.now, duration: 2 * 3600)

        #expect(state.visibleMoodChanges(from: Dates.now, until: Dates.hours(12), boosts: []).isEmpty,
                "a flat curve with no boost schedules nothing")

        // 48 + 10 decaying over 2h drops through 50 when 8 of the lift is
        // spent: at 80% of the duration.
        let changes = state.visibleMoodChanges(from: Dates.now, until: Dates.hours(12), boosts: [boost])
        #expect(changes.count == 1)
        #expect(abs((changes.first?.timeIntervalSince(Dates.now) ?? 0) - 0.8 * 2 * 3600) <= 60)
    }
}

@Suite("WidgetStateStore")
struct WidgetStateStoreTests {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "widget-store-tests-\(UUID())")!
    }

    @Test("the snapshot round-trips, and an unknown schema version reads as absent")
    func roundTripAndVersionGate() throws {
        let defaults = freshDefaults()
        let state = makeState(
            displayState: .vacation,
            baseline: [.init(date: Dates.now, value: 58)],
            nextTasks: [.init(id: "t1", title: "Water plants", dueAt: Dates.hours(2), hasTime: true, completable: true)],
            vacationEnd: Dates.days(2)
        )
        WidgetStateStore.save(state, defaults: defaults)
        #expect(WidgetStateStore.load(defaults: defaults) == state)

        var future = state
        future.schemaVersion = 2
        WidgetStateStore.save(future, defaults: defaults)
        #expect(WidgetStateStore.load(defaults: defaults) == nil,
                "an older widget must ignore a newer contract, not misread it")
    }

    @Test("the completion queue dedupes, keeps tap-time context, and drains to empty")
    func completionQueue() {
        let defaults = freshDefaults()
        let evening = CompletionLocalContext(
            localDate: "2026-07-07", localMinute: 22 * 60, timeZoneId: "America/Chicago"
        )
        WidgetStateStore.enqueueCompletion(taskId: "a", context: evening, defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "b", context: .capture(), defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "a", context: .capture(), defaults: defaults)

        let pending = WidgetStateStore.pendingCompletions(defaults: defaults)
        #expect(pending.map(\.taskId) == ["a", "b"])
        // The context stamped at TAP time survives verbatim - an overnight
        // drain cannot shift evening behavior into morning.
        #expect(pending.first?.context == evening)
        #expect(WidgetStateStore.drainCompletions(defaults: defaults) == pending)
        #expect(WidgetStateStore.pendingCompletions(defaults: defaults).isEmpty)
    }

    @Test("a pre-context string-array queue still drains, with context honestly absent")
    func completionQueueLegacyFormat() {
        let defaults = freshDefaults()
        defaults.set(["old1", "old2"], forKey: WidgetStateStore.completionQueueKey)

        let drained = WidgetStateStore.drainCompletions(defaults: defaults)
        #expect(drained.map(\.taskId) == ["old1", "old2"])
        #expect(drained.allSatisfy { $0.context == nil },
                "legacy entries must fall back to derived context, never fake a stamp")
    }

    @Test("the comfort buffer migrates from standard defaults into the group once")
    func bufferMigration() {
        let old = freshDefaults()
        let group = freshDefaults()
        UserDefaultsComfortBufferStore(defaults: old).add(lift: 8, duration: 900)

        UserDefaultsComfortBufferStore.migrateToAppGroup(from: old, to: group)

        #expect(!UserDefaultsComfortBufferStore(defaults: group).activeBoosts(now: .now).isEmpty)
        #expect(old.data(forKey: "mochi.comfortBoosts") == nil, "moved, not copied")

        // A second migration never clobbers live group data.
        UserDefaultsComfortBufferStore(defaults: old).add(lift: 20, duration: 900)
        UserDefaultsComfortBufferStore.migrateToAppGroup(from: old, to: group)
        let boosts = UserDefaultsComfortBufferStore(defaults: group).activeBoosts(now: .now)
        #expect(boosts.count == 1)
        #expect(boosts.first?.lift == 8)
    }
}

@Suite("WidgetStateMirror")
@MainActor
struct WidgetStateMirrorTests {

    private func mirror(
        context: NotificationOrchestrator.RelayContext,
        now: Date = Dates.now
    ) -> (MochiWidgetState?, reloaded: Bool) {
        let defaults = UserDefaults(suiteName: "mirror-tests-\(UUID())")!
        var reloaded = false
        let mirror = WidgetStateMirror(
            themeStore: ThemeStore(defaults: UserDefaults(suiteName: "mirror-theme-\(UUID())")!),
            defaults: defaults,
            reloadWidgets: { reloaded = true }
        )
        mirror.mirror(context: context, now: now)
        return (WidgetStateStore.load(defaults: defaults), reloaded)
    }

    private func makeContext(
        tasks: [TaskItem] = [],
        lapsed: Bool = false,
        vacationMode: Bool = false,
        vacationResumeAt: Date? = nil,
        vacationStartedAt: Date? = nil,
        hideTaskNames: Bool = false,
        petName: String = "Mochi"
    ) -> NotificationOrchestrator.RelayContext {
        var prefs = NotificationPrefs.standard
        prefs.hideTaskNames = hideTaskNames
        return NotificationOrchestrator.RelayContext(
            userId: "user1",
            snapshot: MoodSnapshot(
                tasks: tasks, completionTimes: [], boosts: [],
                vacationMode: vacationMode, vacationResumeAt: vacationResumeAt,
                vacationStartedAt: vacationStartedAt,
                entitlementExpiry: nil, capturedAt: Dates.now
            ),
            prefs: prefs,
            bedtime: .standard,
            lapsed: lapsed,
            petName: petName
        )
    }

    @Test("the mirror writes the pet name into the snapshot for widget chrome")
    func mirrorsPetName() {
        let (state, _) = mirror(context: makeContext(petName: "Nori"))
        #expect(state?.petDisplayName == "Nori")
    }

    @Test("the mirrored curve IS the engine's baseline, point for point, with the ranked next tasks")
    func mirrorsTheOneCurve() {
        let tasks = [
            makeTask(id: "over", title: "Pay rent", dueAt: Dates.hours(-3), hasTime: true, priority: .high),
            makeTask(id: "later", title: "Call gran", dueAt: Dates.hours(5), hasTime: true),
        ]
        let context = makeContext(tasks: tasks)
        let (state, reloaded) = mirror(context: context)

        #expect(reloaded)
        #expect(state?.displayState == .active)
        guard let state else { return }
        #expect(state.baseline.count > 300, "7 days at half-hour resolution")
        for point in state.baseline.prefix(8) {
            #expect(point.value == MoodForecast.baseline(at: point.date, snapshot: context.snapshot),
                    "widget curve must equal mood(t) - same invariant as the pings")
        }
        #expect(state.nextTasks.first?.title == "Pay rent", "overdue leads the rundown ranking")
        #expect(state.nextTasks.allSatisfy { $0.completable })
    }

    @Test("lapsed and vacation map to their distinct display states, never conflated")
    func displayStates() {
        let (lapsed, _) = mirror(context: makeContext(lapsed: true))
        #expect(lapsed?.displayState == .lapsed)
        #expect(lapsed?.vacationEnd == nil)

        let (vacation, _) = mirror(context: makeContext(
            vacationMode: true,
            vacationResumeAt: Dates.days(3),
            vacationStartedAt: Dates.days(-1)
        ))
        #expect(vacation?.displayState == .vacation)
        #expect(vacation?.vacationEnd == Dates.days(3))
    }

    @Test("the lock-screen privacy toggle rides the contract")
    func privacyRides() {
        let (state, _) = mirror(context: makeContext(hideTaskNames: true))
        #expect(state?.hideTaskNames == true)
    }
}

@Suite("WidgetCompletionDrain")
@MainActor
struct WidgetCompletionDrainTests {

    @Test("queued widget completions land through the completion store - coins included; gone tasks drop")
    func drainLands() async {
        let defaults = UserDefaults(suiteName: "drain-tests-\(UUID())")!
        let auth = StubAuthRepository()
        let profileRepo = StubProfileRepository()
        let taskRepo = StubTaskRepository()
        taskRepo.incomplete = [makeTask(id: "t1", dueAt: Dates.hours(-1), hasTime: true)]
        taskRepo.completed = [makeTask(id: "done", completed: true, completedAt: Dates.now)]
        let drain = WidgetCompletionDrain(
            authRepository: auth,
            taskRepository: taskRepo,
            profileRepository: profileRepo,
            completionStore: TaskCompletionStore(
                taskRepository: taskRepo,
                rewardsStore: RewardsStore(profileRepository: profileRepo),
                membershipSession: MembershipSession()
            ),
            defaults: defaults
        )
        let tapContext = CompletionLocalContext(
            localDate: "2026-07-07", localMinute: 21 * 60 + 30, timeZoneId: "America/Chicago"
        )
        WidgetStateStore.enqueueCompletion(taskId: "t1", context: tapContext, defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "done", context: .capture(), defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "ghost", context: .capture(), defaults: defaults)

        let landed = await drain.drain()

        #expect(landed == 1)
        #expect(taskRepo.setCompletedCalls.map(\.taskId) == ["t1"])
        #expect(taskRepo.setCompletedContexts == [tapContext],
                "the drain must persist the context stamped at tap time")
        #expect(profileRepo.coinDeltas == [RewardsStore.coinsPerTask])
        #expect(WidgetStateStore.pendingCompletions(defaults: defaults).isEmpty)

        // Nothing left: a second drain is a quiet no-op.
        let second = await drain.drain()
        #expect(second == 0)
    }
}
