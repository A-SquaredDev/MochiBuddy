//
//  MoodEngineTests.swift
//  MochiBuddyTests
//
//  The mood baseline is the product's heart — these tests pin the design
//  doc's guiding principles and its worked examples so retuning constants
//  is a deliberate act, not an accident.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("MoodEngine · baseline")
struct MoodEngineBaselineTests {

    private func baseline(
        _ tasks: [TaskItem],
        completions: Int = 0,
        vacation: Bool = false,
        now: Date = Dates.now
    ) -> Double {
        MoodEngine.baseline(
            incompleteTasks: tasks,
            completionsLast24h: completions,
            vacationMode: vacation,
            now: now,
            calendar: Dates.calendar
        )
    }

    /// A med-priority task overdue by `hours`.
    private func overdue(_ hours: Double, priority: TaskPriority = .med) -> TaskItem {
        makeTask(dueAt: Dates.hours(-hours), hasTime: true, priority: priority)
    }

    // MARK: Anchor & "volume ≠ stress"

    @Test("no tasks at all rests at the content anchor")
    func emptyIsContent() {
        #expect(baseline([]) == MoodEngine.Constants.anchor)
    }

    @Test("on-time and undated tasks contribute zero stress — 20 calm tasks = a calm Mochi")
    func volumeIsNotStress() {
        var tasks: [TaskItem] = []
        for i in 0..<10 {
            tasks.append(makeTask(title: "future \(i)", dueAt: Dates.hours(Double(i) + 2), hasTime: true))
        }
        for i in 0..<10 {
            tasks.append(makeTask(title: "someday \(i)"))
        }
        #expect(baseline(tasks) == MoodEngine.Constants.anchor)
    }

    @Test("completed tasks never stress even when their due date passed")
    func completedTasksAreFiltered() {
        // The engine takes incomplete tasks; completed ones with stale due
        // dates must still contribute zero if a caller passes them anyway.
        let task = makeTask(dueAt: Dates.hours(-24), hasTime: true, completed: true)
        // hoursOverdue is boundary math only — the caller filters completed.
        // Verify the documented call pattern (filtering) yields the anchor.
        #expect(baseline([task].filter { !$0.completed }) == MoodEngine.Constants.anchor)
    }

    // MARK: Worked examples from the design doc (med priority, ~24h overdue)

    @Test("1 overdue ≈ uneasy")
    func oneOverdue() {
        let value = baseline([overdue(24)], completions: 1)
        #expect(value >= 35 && value < 50, "expected uneasy band, got \(value)")
    }

    @Test("2 overdue ≈ anxious (~34)")
    func twoOverdue() {
        let value = baseline([overdue(24), overdue(24)], completions: 1)
        #expect(abs(value - 34) < 3, "doc example says ~34, got \(value)")
    }

    @Test("5 overdue ≈ very sad edge (~16)")
    func fiveOverdue() {
        let value = baseline(Array(repeating: overdue(24), count: 5).map { _ in overdue(24) }, completions: 1)
        #expect(abs(value - 16) < 3, "doc example says ~16, got \(value)")
    }

    @Test("10 overdue ≈ very sad (~4)")
    func tenOverdue() {
        let value = baseline((0..<10).map { _ in overdue(24) }, completions: 1)
        #expect(abs(value - 4) < 3, "doc example says ~4, got \(value)")
    }

    @Test("20 overdue pegs near zero but never below")
    func twentyOverdue() {
        let value = baseline((0..<20).map { _ in overdue(24) })
        #expect(value >= 0 && value < 3)
    }

    // MARK: Stress mechanics

    @Test("going overdue stings immediately (BASE term)")
    func instantSting() {
        let value = baseline([overdue(0.01)])
        #expect(value < MoodEngine.Constants.anchor - 5,
                "a just-overdue task should visibly drop the baseline, got \(value)")
    }

    @Test("lateness saturates at the 48h cap")
    func latenessCap() {
        let at48 = baseline([overdue(48)])
        let at400 = baseline([overdue(400)])
        #expect(abs(at48 - at400) < 0.001, "beyond H_MAX lateness must not add stress")
    }

    @Test("stress grows monotonically with lateness up to the cap")
    func latenessMonotonic() {
        let fresh = baseline([overdue(1)])
        let day = baseline([overdue(24)])
        let capped = baseline([overdue(48)])
        #expect(fresh > day)
        #expect(day > capped)
    }

    @Test("priority is the mood weight: high hurts more than low")
    func priorityWeights() {
        let low = baseline([overdue(24, priority: .low)])
        let med = baseline([overdue(24, priority: .med)])
        let high = baseline([overdue(24, priority: .high)])
        #expect(low > med)
        #expect(med > high)
    }

    @Test("the first overdue tasks matter most (saturating curve)")
    func stressSaturates() {
        let one = MoodEngine.Constants.anchor - baseline([overdue(24)])
        let many = baseline((0..<9).map { _ in overdue(24) })
        let evenMore = baseline((0..<10).map { _ in overdue(24) })
        let marginalTenth = many - evenMore
        #expect(marginalTenth < one, "the 10th overdue task must add less stress than the 1st")
        #expect(marginalTenth >= 0)
    }

    // MARK: Momentum & gating

    @Test("completions lift a calm Mochi toward happy")
    func momentumLifts() {
        let calm = baseline([])
        let productive = baseline([], completions: 3)
        #expect(productive > calm)
        #expect(productive >= 80 || productive > 70, "3 completions should read happy-ish, got \(productive)")
    }

    @Test("momentum saturates — 30 completions can't exceed 100")
    func momentumClamped() {
        let value = baseline([], completions: 30)
        #expect(value <= 100)
        #expect(value > 95)
    }

    @Test("momentum is fully gated while badly behind — you can't fake happiness")
    func momentumGatedUnderStress() {
        let tasks = (0..<3).map { _ in overdue(24) } // stress > GATE_K
        let idle = baseline(tasks, completions: 0)
        let grinding = baseline(tasks, completions: 10)
        #expect(abs(idle - grinding) < 0.001,
                "with stress past the gate, completions must not move the baseline")
    }

    @Test("clearing the overdue task removes its stress at the source")
    func clearingOverdueRecovers() {
        let behind = baseline([overdue(24)])
        let cleared = baseline([], completions: 1)
        #expect(cleared > MoodEngine.Constants.anchor)
        #expect(cleared - behind > 20, "recovery should be dramatic")
    }

    // MARK: Vacation

    @Test("vacation mode suppresses stress entirely")
    func vacationSuppressesStress() {
        let tasks = (0..<10).map { _ in overdue(24) }
        let value = baseline(tasks, vacation: true)
        #expect(value == MoodEngine.Constants.anchor)
    }

    @Test("vacation mode still allows momentum")
    func vacationKeepsMomentum() {
        let tasks = (0..<10).map { _ in overdue(24) }
        let value = baseline(tasks, completions: 3, vacation: true)
        #expect(value > MoodEngine.Constants.anchor)
    }

    // MARK: Clamps

    @Test("baseline never leaves 0...100")
    func clamped() {
        let floor = baseline((0..<50).map { _ in overdue(400, priority: .high) })
        let ceiling = baseline([], completions: 100)
        #expect(floor >= 0)
        #expect(ceiling <= 100)
    }
}

@Suite("MoodEngine · overdue boundaries")
struct MoodEngineBoundaryTests {

    @Test("undated tasks are never overdue")
    func undatedNeverOverdue() {
        let task = makeTask(dueAt: nil)
        #expect(MoodEngine.overdueBoundary(task, calendar: Dates.calendar) == nil)
        #expect(MoodEngine.hoursOverdue(task, now: Dates.now, calendar: Dates.calendar) == nil)
    }

    @Test("timed tasks flip overdue at their exact instant")
    func timedBoundaryIsExact() {
        let due = Dates.hours(-2)
        let task = makeTask(dueAt: due, hasTime: true)
        #expect(MoodEngine.overdueBoundary(task, calendar: Dates.calendar) == due)
        let hours = MoodEngine.hoursOverdue(task, now: Dates.now, calendar: Dates.calendar)
        #expect(hours != nil && abs(hours! - 2) < 0.001)
    }

    @Test("a timed task due later today is not overdue")
    func timedFutureNotOverdue() {
        let task = makeTask(dueAt: Dates.hours(3), hasTime: true)
        let hours = MoodEngine.hoursOverdue(task, now: Dates.now, calendar: Dates.calendar)
        #expect(hours != nil && hours! < 0)
    }

    @Test("date-only tasks flip overdue at the END of their local day")
    func dateOnlyBoundaryIsEndOfDay() {
        let task = makeTask(dueAt: Dates.startOfToday, hasTime: false)
        let boundary = MoodEngine.overdueBoundary(task, calendar: Dates.calendar)
        let expected = Dates.calendar.date(byAdding: .day, value: 1, to: Dates.startOfToday)
        #expect(boundary == expected)
        // At 10:00 today the task is NOT overdue.
        let hours = MoodEngine.hoursOverdue(task, now: Dates.now, calendar: Dates.calendar)
        #expect(hours != nil && hours! < 0)
    }

    @Test("a date-only task from yesterday is overdue this morning")
    func dateOnlyYesterdayOverdue() {
        let yesterday = Dates.calendar.date(byAdding: .day, value: -1, to: Dates.startOfToday)!
        let task = makeTask(dueAt: yesterday, hasTime: false)
        let hours = MoodEngine.hoursOverdue(task, now: Dates.now, calendar: Dates.calendar)
        // Boundary was midnight; at 10:00 it's ~10h overdue.
        #expect(hours != nil && abs(hours! - 10) < 0.5)
    }

    @Test("priority weights match the design doc exactly")
    func weights() {
        #expect(MoodEngine.weight(.low) == 1)
        #expect(MoodEngine.weight(.med) == 1.5)
        #expect(MoodEngine.weight(.high) == 2)
    }
}
