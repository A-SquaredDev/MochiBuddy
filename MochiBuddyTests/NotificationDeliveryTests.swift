//
//  NotificationDeliveryTests.swift
//  MochiBuddyTests
//
//  The delivery layer around the planner: taper state machine, copy
//  voices and rotation, rundown ranking, snooze targets, repeating
//  triggers, request dressing, and the orchestrator composition against
//  a stubbed notification center.
//
//  Dates.now anchor: Wed 8 Jul 2026, 10:00 local.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("TaperTracker")
struct TaperTrackerTests {

    @Test("first floor sighting starts the stretch at day 1")
    func stretchStarts() {
        let state = TaperTracker.update(TaperState(), band: .verySad, now: Dates.now)
        #expect(state.firstFloorDay == Dates.startOfToday)
        #expect(state.consecutiveFloorDays(before: Dates.now) == 0, "today is day 1")
    }

    @Test("the stretch carries across unobserved gaps - no action means the floor persisted")
    func stretchCarriesAcrossGaps() {
        var state = TaperTracker.update(TaperState(), band: .verySad, now: Dates.now)
        // Nothing observed for three days (app closed), floor again.
        state = TaperTracker.update(state, band: .verySad, now: Dates.days(3))
        #expect(state.firstFloorDay == Dates.startOfToday)
        #expect(state.consecutiveFloorDays(before: Dates.days(3)) == 3, "day 4 of the stretch")
    }

    @Test("a blip up that slides back never resets the taper")
    func blipDoesNotReset() {
        var state = TaperTracker.update(TaperState(), band: .verySad, now: Dates.now)
        // One completion pops the mood, it slides back within hours.
        state = TaperTracker.update(state, band: .content, now: Dates.hours(2))
        state = TaperTracker.update(state, band: .verySad, now: Dates.hours(5))
        state = TaperTracker.update(state, band: .verySad, now: Dates.days(1))
        #expect(state.consecutiveFloorDays(before: Dates.days(1)) == 1,
                "still day 2 - the blip must not hand out MORE pings than doing nothing")
    }

    @Test("a genuine recovery (good band held 24h) clears the stretch")
    func heldRecoveryClears() {
        var state = TaperTracker.update(TaperState(), band: .verySad, now: Dates.now)
        state = TaperTracker.update(state, band: .content, now: Dates.hours(3))
        state = TaperTracker.update(state, band: .happy, now: Dates.hours(3 + 25))
        #expect(state.firstFloorDay == nil)
        #expect(state.consecutiveFloorDays(before: Dates.days(2)) == 0)
    }

    @Test("anxious in between interrupts the recovery clock but keeps the stretch")
    func anxiousInterruptsRecovery() {
        var state = TaperTracker.update(TaperState(), band: .verySad, now: Dates.now)
        state = TaperTracker.update(state, band: .content, now: Dates.hours(2))
        state = TaperTracker.update(state, band: .anxious, now: Dates.hours(12))
        state = TaperTracker.update(state, band: .content, now: Dates.hours(14))
        // 24h after the FIRST content sighting, but the hold restarted.
        state = TaperTracker.update(state, band: .content, now: Dates.hours(27))
        #expect(state.firstFloorDay != nil, "recovery must be held continuously")
    }
}

@Suite("NotificationCopy")
struct NotificationCopyTests {

    @Test("rotation never repeats a line until the pool cycles")
    func rotationCycles() {
        var deck = CopyDeck()
        let pool = NotificationCopy.anxiousPool
        var seen: [String] = []
        for _ in pool {
            seen.append(deck.next(from: pool, key: "anxious"))
        }
        #expect(Set(seen).count == pool.count, "every line used once before any repeat")
        #expect(deck.next(from: pool, key: "anxious") == seen[0], "then it cycles")
    }

    @Test("floor copy shifts pools with the taper: acute early, pure presence later")
    func floorPools() {
        var deck = CopyDeck()
        let acute = NotificationCopy.moodPing(band: .verySad, floorPhase: .acute, deck: &deck)
        let chronic = NotificationCopy.moodPing(band: .verySad, floorPhase: .chronic, deck: &deck)
        #expect(NotificationCopy.floorAcutePool.contains(acute.body))
        #expect(NotificationCopy.floorChronicPool.contains(chronic.body))
    }

    @Test("mood copy carries no emoji and no em dash, ever")
    func moodCopyIsClean() {
        let pools = NotificationCopy.uneasyPool + NotificationCopy.anxiousPool
            + NotificationCopy.floorAcutePool + NotificationCopy.floorChronicPool
        for line in pools {
            #expect(!line.contains("—"), "em dash in: \(line)")
            #expect(
                !line.unicodeScalars.contains { $0.properties.isEmojiPresentation },
                "emoji outside celebrations in: \(line)"
            )
        }
    }

    @Test("reminders name the task; the privacy toggle swaps in the nameless variant")
    func reminderPrivacy() {
        let named = NotificationCopy.reminder(taskTitle: "Call the dentist", hideTaskNames: false)
        #expect(named.title == "Call the dentist")

        let hidden = NotificationCopy.reminder(taskTitle: "Call the dentist", hideTaskNames: true)
        #expect(!hidden.title.contains("dentist"))
        #expect(!hidden.body.contains("dentist"))
    }

    @Test("the rundown flexes tone to load and keeps names off the lock screen when asked")
    func rundownTone() {
        let calm = NotificationCopy.rundown(taskTitles: [], hideTaskNames: false)
        #expect(calm.title == "A calm day")

        let full = NotificationCopy.rundown(
            taskTitles: ["Pay rent", "Gym", "Groceries"], hideTaskNames: false
        )
        #expect(full.body == "Pay rent · Gym · Groceries")

        let hidden = NotificationCopy.rundown(
            taskTitles: ["Pay rent", "Gym"], hideTaskNames: true
        )
        #expect(!hidden.body.contains("rent"))
        #expect(hidden.body.contains("2"))
    }
}

@Suite("RundownRanker")
struct RundownRankerTests {

    @Test("ranking: overdue by lateness, then timed today by time, then date-only by priority, max 3")
    func rankingOrder() {
        let fireAt = Dates.calendar.date(
            byAdding: .minute, value: 7 * 60, to: Dates.calendar.startOfDay(for: Dates.days(1))
        )! // tomorrow 07:00
        let tasks = [
            makeTask(id: "later", title: "Later", dueAt: Dates.days(3), hasTime: true),
            makeTask(id: "noon", title: "Noon", dueAt: Dates.hours(26), hasTime: true),
            makeTask(id: "oldest", title: "Oldest", dueAt: Dates.days(-2), hasTime: true),
            makeTask(id: "younger", title: "Younger", dueAt: Dates.hours(-6), hasTime: true),
            makeTask(id: "chore", title: "Chore", dueAt: Dates.days(1)),
            makeTask(id: "done", title: "Done", dueAt: Dates.days(-3), hasTime: true, completed: true),
        ]
        let top = RundownRanker.topTasks(from: tasks, at: fireAt)
        #expect(top.map(\.id) == ["oldest", "younger", "noon"],
                "lateness descending, then today's timed; the cap squeezed out the date-only chore")
    }

    @Test("date-only tasks rank by priority when there's room")
    func dateOnlyPriority() {
        let fireAt = Dates.calendar.date(
            byAdding: .minute, value: 7 * 60, to: Dates.calendar.startOfDay(for: Dates.days(1))
        )!
        let tasks = [
            makeTask(id: "low", dueAt: Dates.days(1), priority: .low),
            makeTask(id: "high", dueAt: Dates.days(1), priority: .high),
            makeTask(id: "med", dueAt: Dates.days(1), priority: .med),
        ]
        let top = RundownRanker.topTasks(from: tasks, at: fireAt)
        #expect(top.map(\.id) == ["high", "med", "low"])
    }

    @Test("a neglected daily habit is ranked on its rolled-forward occurrence, not the stale date")
    func recurrenceRolledForRanking() {
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 7, hour: 9)
        )! // yesterday 09:00
        let habit = makeTask(id: "habit", dueAt: due, hasTime: true, repeatRule: .daily)
        let fireAt = Dates.calendar.date(
            byAdding: .minute, value: 7 * 60, to: Dates.calendar.startOfDay(for: Dates.days(1))
        )! // tomorrow 07:00

        let top = RundownRanker.topTasks(from: [habit], at: fireAt)
        #expect(top.first?.dueAt == Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)
        ), "the live occurrence is today's, one period late at most")
    }
}

@Suite("SnoozeOption")
struct SnoozeOptionTests {

    @Test("snooze targets from mid-morning: +1h, 19:00 tonight, 09:00 tomorrow")
    func targetsFromMorning() {
        #expect(SnoozeOption.oneHour.targetDate(from: Dates.now) == Dates.hours(1))

        let tonight = SnoozeOption.tonight.targetDate(from: Dates.now)
        var parts = Dates.calendar.dateComponents([.day, .hour], from: tonight)
        #expect((parts.day, parts.hour) == (8, 19))

        let tomorrow = SnoozeOption.tomorrow.targetDate(from: Dates.now)
        parts = Dates.calendar.dateComponents([.day, .hour], from: tomorrow)
        #expect((parts.day, parts.hour) == (9, 9))
    }

    @Test("'tonight' in the late evening still lands an hour out, never in the past")
    func tonightLate() {
        let evening = Dates.hours(10.5) // 20:30
        let target = SnoozeOption.tonight.targetDate(from: evening)
        #expect(target == evening.addingTimeInterval(3600))
    }
}

@Suite("PromiseTriggerBuilder")
struct PromiseTriggerBuilderTests {

    private let nineAM = Dates.calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 10, hour: 9, minute: 30)
    )! // Friday

    @Test("daily, weekly, and monthly cadences repeat in one calendar trigger")
    func repeatableCadences() {
        let daily = PromiseTriggerBuilder.repeatingComponents(for: .daily, dueAt: nineAM)
        #expect((daily?.hour, daily?.minute, daily?.weekday, daily?.day) == (9, 30, nil, nil))

        let weekly = PromiseTriggerBuilder.repeatingComponents(for: .weekly, dueAt: nineAM)
        #expect(weekly?.weekday == 6, "Jul 10 2026 is a Friday")
        #expect((weekly?.hour, weekly?.minute) == (9, 30))

        let monthly = PromiseTriggerBuilder.repeatingComponents(for: .monthly, dueAt: nineAM)
        #expect((monthly?.day, monthly?.hour) == (10, 9))
    }

    @Test("weekdays and custom day sets can't repeat in one trigger - the re-lay refreshes them")
    func nonRepeatableCadences() {
        #expect(PromiseTriggerBuilder.repeatingComponents(for: .weekdays, dueAt: nineAM) == nil)
        #expect(PromiseTriggerBuilder.repeatingComponents(for: .custom([2, 4]), dueAt: nineAM) == nil)
    }
}

@Suite("MembershipSession · change hook")
@MainActor
struct MembershipSessionChangeTests {

    @Test("onChange fires only on a REAL status change - refresh spam never storms the scheduler")
    func onChangeFiresOnRealChange() {
        let session = MembershipSession()
        var fired = 0
        session.onChange = { fired += 1 }

        session.status = .active(plan: .yearly, renewsAt: nil) // same as default
        #expect(fired == 0)
        session.status = .lapsed
        #expect(fired == 1)
        session.status = .lapsed
        #expect(fired == 1)
        session.status = .trial(endsAt: Dates.days(7))
        #expect(fired == 2)
    }
}

@Suite("NotificationID · mood id round-trip")
struct MoodIDParseTests {

    @Test("a mood id parses back to exactly the band and instant baked in")
    func parseRoundTrip() {
        let fireAt = Date(timeIntervalSince1970: 1_780_000_000)
        let id = NotificationID.mood(band: .anxious, fireAt: fireAt)
        let parsed = NotificationID.parseMood(id)
        #expect(parsed?.band == .anxious)
        #expect(parsed?.fireAt == fireAt)
        #expect(NotificationID.parseMood("due-t1") == nil)
        #expect(NotificationID.parseMood("mood-garbage") == nil)
    }
}

@Suite("StreakMilestones")
struct StreakMilestonesTests {

    @Test("sparse trophies: 7, 30, then every 50 days after 30")
    func milestoneSchedule() {
        let milestones = (1...200).filter(StreakMilestones.isMilestone)
        #expect(milestones == [7, 30, 80, 130, 180])
    }
}

@Suite("NotificationRequestBuilder")
struct NotificationRequestBuilderTests {

    private func build(
        _ plan: PlannedNotification,
        tasks: [TaskItem] = [],
        floorPhase: NotificationCopy.FloorPhase = .acute,
        hideTaskNames: Bool = false
    ) -> ScheduledNotificationRequest {
        var deck = CopyDeck()
        return NotificationRequestBuilder.request(
            for: plan,
            tasksById: Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            allTasks: tasks,
            floorPhase: floorPhase,
            hideTaskNames: hideTaskNames,
            deck: &deck
        )
    }

    @Test("a promise is time-sensitive, named, in the reminder category, repeating for a daily rule")
    func promiseDressing() {
        let task = makeTask(id: "t1", title: "Water plants", dueAt: Dates.hours(23), hasTime: true, repeatRule: .daily)
        let request = build(
            PlannedNotification(id: "due-t1", kind: .promise, fireAt: Dates.hours(23), repeats: true, taskId: "t1"),
            tasks: [task]
        )
        #expect(request.content.title == "Water plants")
        #expect(request.urgency == .timeSensitive)
        #expect(request.categoryId == NotificationCategoryID.reminder)
        #expect(request.repeatingComponents != nil)
    }

    @Test("a mood ping is passive, threaded, in the mood category, with pool copy and no task names")
    func moodPingDressing() {
        let request = build(
            PlannedNotification(id: "mood-1-1", kind: .moodPing, fireAt: Dates.hours(2), band: .anxious),
            tasks: [makeTask(id: "secret", title: "Very private thing", dueAt: Dates.hours(-4), hasTime: true)]
        )
        #expect(request.urgency == .passive)
        #expect(request.threadId == "mochi.mood")
        #expect(request.categoryId == NotificationCategoryID.moodPing)
        #expect(NotificationCopy.anxiousPool.contains(request.content.body))
        #expect(!request.content.body.contains("Very private thing"))
    }

    @Test("a rundown is active and carries the ranked top tasks")
    func rundownDressing() {
        let fireAt = Dates.calendar.date(
            byAdding: .minute, value: 7 * 60, to: Dates.calendar.startOfDay(for: Dates.days(1))
        )!
        let request = build(
            PlannedNotification(id: "rundown-2026-07-09", kind: .rundown, fireAt: fireAt),
            tasks: [makeTask(id: "a", title: "Pay rent", dueAt: Dates.hours(-2), hasTime: true)]
        )
        #expect(request.urgency == .active)
        #expect(request.content.body.contains("Pay rent"))
    }

    @Test("a productive yesterday takes over the rundown title - the no-cost celebration beat")
    func crushedYesterdayBeat() {
        let fireAt = Dates.calendar.date(
            byAdding: .minute, value: 7 * 60, to: Dates.calendar.startOfDay(for: Dates.days(1))
        )! // tomorrow 07:00 - "yesterday" is today
        let plan = PlannedNotification(id: "rundown-2026-07-09", kind: .rundown, fireAt: fireAt)
        var deck = CopyDeck()

        let productive = NotificationRequestBuilder.request(
            for: plan, tasksById: [:], allTasks: [],
            completionTimes: (0..<5).map { Dates.hours(Double(-$0)) },
            floorPhase: .acute, hideTaskNames: false, deck: &deck
        )
        #expect(productive.content.title == "You crushed yesterday")

        let ordinary = NotificationRequestBuilder.request(
            for: plan, tasksById: [:], allTasks: [],
            completionTimes: [Dates.hours(-1)],
            floorPhase: .acute, hideTaskNames: false, deck: &deck
        )
        #expect(ordinary.content.title != "You crushed yesterday")
    }

    @Test("the backstop reads as pure presence - safe at any staleness")
    func backstopDressing() {
        let request = build(
            PlannedNotification(id: NotificationID.backstop, kind: .backstop, fireAt: Dates.days(7), repeats: true)
        )
        #expect(request.urgency == .passive)
        #expect(NotificationCopy.floorChronicPool.contains(request.content.body))
    }
}

@Suite("NotificationOrchestrator")
@MainActor
struct NotificationOrchestratorTests {

    private func makeOrchestrator(
        tasks: [TaskItem] = [],
        profile: UserProfile = makeProfile(
            notificationPrefs: {
                var prefs = NotificationPrefs.standard
                prefs.moodDips = true
                return prefs
            }()
        )
    ) -> (NotificationOrchestrator, StubNotificationScheduler, StubTaskRepository, RecordingTelemetry, UserDefaults) {
        let auth = StubAuthRepository()
        let profileRepo = StubProfileRepository()
        profileRepo.profile = profile
        let taskRepo = StubTaskRepository()
        taskRepo.incomplete = tasks
        let scheduler = StubNotificationScheduler()
        let telemetry = RecordingTelemetry()
        let defaults = UserDefaults(suiteName: "orchestrator-tests-\(UUID())")!
        let orchestrator = NotificationOrchestrator(
            authRepository: auth,
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
            bufferStore: StubComfortBufferStore(),
            membershipSession: MembershipSession(),
            scheduler: scheduler,
            telemetry: telemetry,
            defaults: defaults
        )
        return (orchestrator, scheduler, taskRepo, telemetry, defaults)
    }

    private func floorTasks() -> [TaskItem] {
        (0..<10).map { i in
            makeTask(id: "f\(i)", dueAt: Dates.hours(-5), hasTime: true, priority: .high)
        }
    }

    @Test("a relay wipes stale managed ids, schedules the plan, and logs the band it saw")
    func relayAppliesTheDiff() async {
        let (orchestrator, scheduler, _, telemetry, _) = makeOrchestrator(
            tasks: floorTasks() + [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)]
        )
        scheduler.pending = ["mood-3-123", "due-goneTask", "someOtherSDK"]

        await orchestrator.relayNow(.appForeground, now: Dates.now)

        #expect(scheduler.removedIds.contains("mood-3-123"))
        #expect(scheduler.removedIds.contains("due-goneTask"))
        #expect(!scheduler.removedIds.contains("someOtherSDK"))
        #expect(scheduler.scheduled.contains { $0.plan.id == "due-t1" })
        #expect(scheduler.scheduled.contains { $0.plan.kind == .moodPing && $0.plan.band == .verySad })

        guard case .relaid(let trigger, let scheduled, _, let band) = telemetry.events.first else {
            Issue.record("expected a relaid event")
            return
        }
        #expect(trigger == "appForeground")
        #expect(scheduled == scheduler.scheduled.count)
        #expect(band == .verySad)
    }

    @Test("re-laying twice produces the identical id set - idempotent by construction")
    func relayIsIdempotent() async {
        let (orchestrator, scheduler, _, _, _) = makeOrchestrator(tasks: floorTasks())
        await orchestrator.relayNow(.appForeground, now: Dates.now)
        let firstIds = scheduler.scheduled.map(\.plan.id)

        await orchestrator.relayNow(.taskChange, now: Dates.now)
        let secondIds = scheduler.scheduled.dropFirst(firstIds.count).map(\.plan.id)
        #expect(firstIds == secondIds)
    }

    @Test("mood-ping copy rotates across a relay's batch - no two consecutive pings read the same")
    func copyRotatesWithinBatch() async {
        let (orchestrator, scheduler, _, _, _) = makeOrchestrator(tasks: floorTasks())
        await orchestrator.relayNow(.appForeground, now: Dates.now)

        let bodies = scheduler.scheduled
            .filter { $0.plan.kind == .moodPing }
            .map(\.content.body)
        for (a, b) in zip(bodies, bodies.dropFirst()) {
            #expect(a != b)
        }
    }

    @Test("shh: activating silences the next 24h of mood pings and never touches a promise")
    func shhSilences() async {
        let (orchestrator, scheduler, _, _, _) = makeOrchestrator(
            tasks: floorTasks() + [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)]
        )
        await orchestrator.activateShh(now: Dates.now)

        let shhEnd = Dates.now.addingTimeInterval(24 * 3600)
        for request in scheduler.scheduled where request.plan.kind == .moodPing {
            #expect(request.plan.fireAt >= shhEnd)
        }
        #expect(scheduler.scheduled.contains { $0.plan.id == "due-t1" },
                "the promise still fires during shh")
        #expect(orchestrator.shhUntil(now: Dates.now) == shhEnd)
        #expect(orchestrator.shhUntil(now: shhEnd.addingTimeInterval(1)) == nil, "expired shh clears")
    }

    @Test("open-ended vacation relays an empty plan - truly silent")
    func vacationRelaysNothing() async {
        let (orchestrator, scheduler, _, _, _) = makeOrchestrator(
            tasks: floorTasks(),
            profile: makeProfile(vacationMode: true)
        )
        scheduler.pending = ["mood-4-1", "due-f0"]
        await orchestrator.relayNow(.vacationChange, now: Dates.now)

        #expect(scheduler.scheduled.isEmpty)
        #expect(Set(scheduler.removedIds) == ["mood-4-1", "due-f0"], "entering vacation clears the queue")
    }

    @Test("the taper stretch persists across relays via defaults")
    func taperPersists() async {
        let (orchestrator, _, _, _, defaults) = makeOrchestrator(tasks: floorTasks())
        await orchestrator.relayNow(.appForeground, now: Dates.now)
        let data = defaults.data(forKey: "mochi.notif.taper")
        #expect(data != nil)
        let state = try? JSONDecoder().decode(TaperState.self, from: data ?? Data())
        #expect(state?.firstFloorDay == Dates.startOfToday)
    }

    @Test("requestRelay debounces a mutation storm into one lay")
    func debounce() async throws {
        let (orchestrator, _, _, telemetry, _) = makeOrchestrator(tasks: [])
        orchestrator.requestRelay(.taskChange)
        orchestrator.requestRelay(.taskChange)
        orchestrator.requestRelay(.taskChange)
        // Poll generously (the parallel suite can starve timers), then
        // settle - the assertion is the COUNT: one lay, not three.
        for _ in 0..<50 where telemetry.events.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(telemetry.events.count == 1)
    }
}
