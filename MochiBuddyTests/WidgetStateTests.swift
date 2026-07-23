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

    @Test("the completion queue dedupes and drains to empty")
    func completionQueue() {
        let defaults = freshDefaults()
        WidgetStateStore.enqueueCompletion(taskId: "a", defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "b", defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "a", defaults: defaults)

        #expect(WidgetStateStore.pendingCompletions(defaults: defaults) == ["a", "b"])
        #expect(WidgetStateStore.drainCompletions(defaults: defaults) == ["a", "b"])
        #expect(WidgetStateStore.pendingCompletions(defaults: defaults).isEmpty)
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
        WidgetStateStore.enqueueCompletion(taskId: "t1", defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "done", defaults: defaults)
        WidgetStateStore.enqueueCompletion(taskId: "ghost", defaults: defaults)

        let landed = await drain.drain()

        #expect(landed == 1)
        #expect(taskRepo.setCompletedCalls.map(\.taskId) == ["t1"])
        #expect(profileRepo.coinDeltas == [RewardsStore.coinsPerTask])
        #expect(WidgetStateStore.pendingCompletions(defaults: defaults).isEmpty)

        // Nothing left: a second drain is a quiet no-op.
        let second = await drain.drain()
        #expect(second == 0)
    }
}
