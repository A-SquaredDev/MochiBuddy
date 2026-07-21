//
//  NotificationPlannerTests.swift
//  MochiBuddyTests
//
//  The planner is pure: snapshot + prefs in, desired pending set out.
//  These tests encode the design doc's scheduling rules - cadence, floor
//  taper, quiet-hours drop, suppression composition, slot budget - and
//  the consistency invariant (a ping's baked band == mood(fireAt)).
//
//  Dates.now anchor: Wed 8 Jul 2026, 10:00 local. Standard bedtime is
//  22:00-07:00, so wake (rundown time) is 07:00.
//

import Foundation
import Testing
@testable import MochiBuddy

private func makeInput(
    tasks: [TaskItem] = [],
    completionTimes: [Date] = [],
    vacationMode: Bool = false,
    vacationResumeAt: Date? = nil,
    vacationStartedAt: Date? = nil,
    entitlementExpiry: Date? = nil,
    bedtime: BedtimeWindow = .standard,
    taskReminders: Bool = true,
    morningRundown: Bool = false,
    moodDips: Bool = false,
    level: NudgeLevel = .balanced,
    lapsed: Bool = false,
    shhUntil: Date? = nil,
    consecutiveFloorDays: Int = 0,
    horizon: Date = Dates.days(7)
) -> NotificationPlanInput {
    var prefs = NotificationPrefs.standard
    prefs.taskReminders = taskReminders
    prefs.morningRundown = morningRundown
    prefs.moodDips = moodDips
    prefs.level = level
    return NotificationPlanInput(
        snapshot: MoodSnapshot(
            tasks: tasks, completionTimes: completionTimes, boosts: [],
            vacationMode: vacationMode, vacationResumeAt: vacationResumeAt,
            vacationStartedAt: vacationStartedAt,
            entitlementExpiry: entitlementExpiry, capturedAt: Dates.now
        ),
        bedtime: bedtime,
        prefs: prefs,
        lapsed: lapsed,
        shhUntil: shhUntil,
        consecutiveFloorDays: consecutiveFloorDays,
        horizon: horizon
    )
}

/// Ten high tasks overdue for hours - pins the curve to the floor.
private func floorTasks() -> [TaskItem] {
    (0..<10).map { i in
        makeTask(id: "f\(i)", dueAt: Dates.hours(-5), hasTime: true, priority: .high)
    }
}

private func moodPings(_ plan: [PlannedNotification]) -> [PlannedNotification] {
    plan.filter { $0.kind == .moodPing }
}

private func perDayCounts(_ pings: [PlannedNotification]) -> [Int] {
    var byDay: [Date: Int] = [:]
    for ping in pings {
        byDay[Dates.calendar.startOfDay(for: ping.fireAt), default: 0] += 1
    }
    return byDay.keys.sorted().map { byDay[$0]! }
}

@Suite("NotificationPlanner · promises")
struct PlannerPromiseTests {

    @Test("a future timed task gets one exact promise with a stable id")
    func timedTaskPromise() {
        let due = Dates.hours(3)
        let plan = NotificationPlanner.plan(makeInput(
            tasks: [makeTask(id: "t1", dueAt: due, hasTime: true)]
        ))
        let promises = plan.filter { $0.kind == .promise }
        #expect(promises.count == 1)
        #expect(promises.first?.id == "due-t1")
        #expect(promises.first?.fireAt == due)
        #expect(promises.first?.repeats == false)
        #expect(promises.first?.taskId == "t1")
    }

    @Test("date-only and already-due tasks get no promise - the rundown and past lays carry them")
    func noPromiseWithoutFutureInstant() {
        let plan = NotificationPlanner.plan(makeInput(tasks: [
            makeTask(id: "dateOnly", dueAt: Dates.days(1)),
            makeTask(id: "overdue", dueAt: Dates.hours(-1), hasTime: true),
            makeTask(id: "undated"),
        ]))
        #expect(plan.filter { $0.kind == .promise }.isEmpty)
    }

    @Test("an overdue recurring occurrence still promises its NEXT fire - a re-lay in the overdue window must never drop tomorrow's reminder")
    func overdueRecurringPromisesNextOccurrence() {
        // Daily habit due 09:00 today, now 10:00 - overdue but not yet
        // rolled (the roll waits for tomorrow's occurrence to come due).
        let dueAt = Dates.hours(-1)
        let plan = NotificationPlanner.plan(makeInput(
            tasks: [makeTask(id: "habit", dueAt: dueAt, hasTime: true, repeatRule: .daily)]
        ))
        let promises = plan.filter { $0.kind == .promise }
        #expect(promises.count == 1)
        #expect(promises.first?.id == "due-habit")
        #expect(promises.first?.fireAt == Dates.hours(23), "tomorrow 09:00 - the next occurrence")
        #expect(promises.first?.repeats == true)
    }

    @Test("a recurring timed task promises with a repeating trigger - one slot forever")
    func recurringPromiseRepeats() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: [makeTask(id: "habit", dueAt: Dates.hours(23), hasTime: true, repeatRule: .daily)]
        ))
        let promise = plan.first { $0.kind == .promise }
        #expect(promise?.repeats == true)
    }

    @Test("the task-reminders toggle silences promises")
    func taskRemindersOff() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)],
            taskReminders: false
        ))
        #expect(plan.filter { $0.kind == .promise }.isEmpty)
    }
}

@Suite("NotificationPlanner · lapsed & vacation")
struct PlannerSuppressionTests {

    @Test("lapsed: promises persist indefinitely, everything else is silent - the winback is usefulness")
    func lapsedIsPromisesOnly() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks() + [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)],
            morningRundown: true,
            moodDips: true,
            lapsed: true
        ))
        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { $0.kind == .promise })
    }

    @Test("vacation is truly silent: even promises inside the window drop; after resume everything returns")
    func vacationSilencesTheWindow() {
        let resumeAt = Dates.days(2)
        let plan = NotificationPlanner.plan(makeInput(
            tasks: [
                makeTask(id: "during", dueAt: Dates.days(1), hasTime: true, priority: .high),
                makeTask(id: "after", dueAt: Dates.days(3), hasTime: true, priority: .high),
            ],
            vacationMode: true,
            vacationResumeAt: resumeAt,
            morningRundown: true,
            moodDips: true
        ))

        #expect(!plan.contains { $0.id == "due-during" }, "no push of any kind while away")
        #expect(plan.contains { $0.id == "due-after" })
        for item in plan {
            #expect(item.fireAt >= resumeAt, "\(item.id) fires during vacation")
        }
    }

    @Test("mood pings stay quiet through the 24h grace window after a vacation ends - promises don't")
    func graceWindowAfterVacation() {
        let resumeAt = Dates.days(1)
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks() + [
                makeTask(id: "t1", dueAt: resumeAt.addingTimeInterval(2 * 3600), hasTime: true),
            ],
            vacationMode: true,
            vacationResumeAt: resumeAt,
            vacationStartedAt: Dates.days(-2),
            moodDips: true
        ))

        let graceEnd = resumeAt.addingTimeInterval(VacationConstants.graceDecay)
        let pings = moodPings(plan)
        #expect(!pings.isEmpty, "pings resume after the grace window inside the horizon")
        #expect(pings.allSatisfy { $0.fireAt >= graceEnd },
                "no sad ping lands during the gentle wake")
        #expect(plan.contains { $0.id == "due-t1" }, "the post-vacation promise is untouched by grace")
    }

    @Test("open-ended vacation plans nothing at all")
    func openEndedVacationPlansNothing() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks() + [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)],
            vacationMode: true,
            morningRundown: true,
            moodDips: true
        ))
        #expect(plan.isEmpty)
    }

    @Test("shh: mood pings before the expiry drop, and it resumes at the tapered cadence, not day 1")
    func shhSuppressesAndResumesTapered() {
        let shhUntil = Dates.days(1) // Thu 10:00
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks(),
            moodDips: true,
            shhUntil: shhUntil
        ))
        let pings = moodPings(plan)
        #expect(!pings.isEmpty)
        #expect(pings.allSatisfy { $0.fireAt >= shhUntil })

        // Thursday is floor day 2 regardless of the shh - budget 3.
        let thursday = Dates.calendar.startOfDay(for: shhUntil)
        let thursdayPings = pings.filter {
            Dates.calendar.startOfDay(for: $0.fireAt) == thursday
        }
        #expect(thursdayPings.count == 3, "shh must not reset the taper")
    }
}

@Suite("NotificationPlanner · cadence & taper")
struct PlannerCadenceTests {

    @Test("the floor taper: 4, 3, 2, then 1/day indefinitely, all spaced, none at night")
    func floorTaperShape() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks(),
            moodDips: true
        ))
        let pings = moodPings(plan)

        #expect(perDayCounts(pings) == [4, 3, 2, 1, 1, 1, 1, 1])
        #expect(pings.allSatisfy { $0.band == .verySad })

        let sorted = pings.map(\.fireAt).sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            #expect(b.timeIntervalSince(a) >= 2 * 3600 - 1, "floor spacing is 2h")
        }
        for ping in pings {
            #expect(!BedtimeWindow.standard.contains(ping.fireAt),
                    "quiet-hours fires are dropped, never shifted into the night")
        }
    }

    @Test("prior floor days carry into the lay - day 4 of a bad stretch is already 1/day")
    func floorTaperCarriesPriorDays() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks(),
            moodDips: true,
            consecutiveFloorDays: 3
        ))
        #expect(perDayCounts(moodPings(plan)) == [1, 1, 1, 1, 1, 1, 1, 1])
    }

    @Test("anxious cadence: at most 3/day, 3h apart")
    func anxiousCadence() {
        // Two high tasks a day overdue: R=2.8 → ~29, anxious - and they
        // stay anxious even fully aged (R=4 → ~21).
        let tasks = [
            makeTask(id: "a", dueAt: Dates.hours(-24), hasTime: true, priority: .high),
            makeTask(id: "b", dueAt: Dates.hours(-24), hasTime: true, priority: .high),
        ]
        let plan = NotificationPlanner.plan(makeInput(tasks: tasks, moodDips: true))
        let pings = moodPings(plan)

        #expect(!pings.isEmpty)
        #expect(pings.allSatisfy { $0.band == .anxious })
        #expect(perDayCounts(pings).allSatisfy { $0 <= 3 })
        let sorted = pings.map(\.fireAt).sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            #expect(b.timeIntervalSince(a) >= 3 * 3600 - 1)
        }
    }

    @Test("the global ceiling holds across a mid-day band change: never more than 4 mood pings a day")
    func globalDailyCeiling() {
        // Anxious morning, then a plunge to the floor at 14:00.
        let tasks = [
            makeTask(id: "a", dueAt: Dates.hours(-24), hasTime: true, priority: .high),
            makeTask(id: "b", dueAt: Dates.hours(-24), hasTime: true, priority: .high),
        ] + (0..<8).map { i in
            makeTask(id: "p\(i)", dueAt: Dates.hours(4), hasTime: true, priority: .high)
        }
        let plan = NotificationPlanner.plan(makeInput(tasks: tasks, moodDips: true))
        let counts = perDayCounts(moodPings(plan))
        #expect(counts.allSatisfy { $0 <= NotificationPlanner.Constants.moodPingsPerDayCeiling })
        #expect(counts.first == 4, "the capture day fills to exactly the ceiling")
    }

    @Test("'rarely' caps every band at one gentle ping a day - quieter must never mean the OS off switch")
    func rarelyDialCaps() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks(),
            moodDips: true,
            level: .rarely
        ))
        #expect(perDayCounts(moodPings(plan)).allSatisfy { $0 == 1 })
    }

    @Test("content is silence: an on-track user gets zero mood pings")
    func contentIsSilence() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: [makeTask(id: "future", dueAt: Dates.days(6), hasTime: true)],
            moodDips: true,
            horizon: Dates.days(3)
        ))
        #expect(moodPings(plan).isEmpty)
    }

    @Test("mood-dips off silences pings and the backstop, but not promises")
    func moodDipsOff() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks() + [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)],
            moodDips: false
        ))
        #expect(moodPings(plan).isEmpty)
        #expect(!plan.contains { $0.kind == .backstop })
        #expect(plan.contains { $0.kind == .promise })
    }
}

@Suite("NotificationPlanner · rundown & backstop")
struct PlannerRundownTests {

    @Test("one rundown per morning at wake, starting tomorrow, with date-stamped ids")
    func rundownDailyAtWake() {
        let plan = NotificationPlanner.plan(makeInput(morningRundown: true))
        let rundowns = plan.filter { $0.kind == .rundown }

        #expect(rundowns.count == 7)
        #expect(rundowns.first?.id == "rundown-2026-07-09")
        for rundown in rundowns {
            let parts = Dates.calendar.dateComponents([.hour, .minute], from: rundown.fireAt)
            #expect((parts.hour, parts.minute) == (7, 0), "wake = the end of the bedtime window")
        }
    }

    @Test("the rundown follows a custom wake time")
    func rundownFollowsBedtime() {
        let bedtime = BedtimeWindow(startMinutes: 23 * 60, endMinutes: 6 * 60 + 30)
        let plan = NotificationPlanner.plan(makeInput(bedtime: bedtime, morningRundown: true))
        let first = plan.first { $0.kind == .rundown }
        let parts = Dates.calendar.dateComponents([.hour, .minute], from: first?.fireAt ?? .distantPast)
        #expect((parts.hour, parts.minute) == (6, 30))
    }

    @Test("rundown off means no rundowns")
    func rundownOff() {
        let plan = NotificationPlanner.plan(makeInput(morningRundown: false))
        #expect(!plan.contains { $0.kind == .rundown })
    }

    @Test("one repeating backstop rides along whenever mood pings are on")
    func backstopReserved() {
        let plan = NotificationPlanner.plan(makeInput(moodDips: true))
        let backstops = plan.filter { $0.kind == .backstop }
        #expect(backstops.count == 1)
        #expect(backstops.first?.repeats == true)
        #expect(backstops.first?.id == NotificationID.backstop)
    }
}

@Suite("NotificationPlanner · budget & identity")
struct PlannerBudgetTests {

    @Test("under promise pressure mood pings degrade to zero and no reminder is ever dropped unfairly")
    func promisePressure() {
        // 70 future timed tasks: more promises than slots exist.
        let tasks = (0..<70).map { i in
            makeTask(id: "t\(i)", dueAt: Dates.hours(Double(i) + 1), hasTime: true, priority: .high)
        }
        let plan = NotificationPlanner.plan(makeInput(
            tasks: tasks, morningRundown: true, moodDips: true
        ))

        #expect(plan.count == NotificationPlanner.Constants.slotCap)
        let promises = plan.filter { $0.kind == .promise }
        #expect(promises.count == NotificationPlanner.Constants.slotCap - 1)
        #expect(plan.filter { $0.kind == .backstop }.count == 1)
        #expect(moodPings(plan).isEmpty, "mood pings degrade first - the widget carries")
        #expect(!plan.contains { $0.kind == .rundown })

        // Nearest dues won: the kept promises are t0...t62.
        let keptIds = Set(promises.map(\.id))
        for i in 0..<63 {
            #expect(keptIds.contains("due-t\(i)"))
        }
    }

    @Test("every id in a busy plan is unique and correctly classed for the scoped wipe")
    func idsAreUniqueAndScoped() {
        let plan = NotificationPlanner.plan(makeInput(
            tasks: floorTasks() + [makeTask(id: "t1", dueAt: Dates.hours(3), hasTime: true)],
            morningRundown: true,
            moodDips: true
        ))
        let ids = plan.map(\.id)
        #expect(Set(ids).count == ids.count)

        for item in plan {
            switch item.kind {
            case .moodPing, .backstop:
                #expect(NotificationID.isMoodManaged(item.id), "\(item.id) must be wipeable")
            case .promise, .rundown:
                #expect(!NotificationID.isMoodManaged(item.id), "\(item.id) must never be wiped by a re-lay")
            }
        }
    }

    @Test("THE INVARIANT: every planned mood ping's baked band equals mood(fireAt) recomputed")
    func consistencyInvariant() {
        let input = makeInput(
            tasks: [
                makeTask(id: "over", dueAt: Dates.hours(-3), hasTime: true, priority: .high),
                makeTask(id: "soon", dueAt: Dates.hours(5), hasTime: true, priority: .high),
                makeTask(id: "later", dueAt: Dates.days(1), hasTime: true),
                makeTask(id: "habit", dueAt: Dates.hours(-1), hasTime: true, repeatRule: .daily),
            ],
            moodDips: true
        )
        let pings = moodPings(NotificationPlanner.plan(input))
        #expect(!pings.isEmpty)
        for ping in pings {
            let recomputed = MoodForecast.band(at: ping.fireAt, snapshot: input.snapshot)
            #expect(ping.band == recomputed,
                    "ping at \(ping.fireAt) baked \(String(describing: ping.band)) but mood(t) says \(recomputed)")
        }
    }
}
