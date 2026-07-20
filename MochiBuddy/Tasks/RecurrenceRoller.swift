//
//  RecurrenceRoller.swift
//  MochiBuddy
//
//  The "one live occurrence" invariant (design doc: Task management →
//  Recurring tasks). A recurring task never stacks: the live occurrence
//  accrues lateness until the next occurrence comes due, then rolls
//  forward and is re-stamped, so lateness never exceeds one period.
//  Missed occurrences are logged silently as a count - they feed streaks
//  and future stats, never a "Missed" list (that's a guilt ledger).
//

import Foundation

@MainActor
final class RecurrenceRoller {

    private let taskRepository: TaskRepository

    init(taskRepository: TaskRepository) {
        self.taskRepository = taskRepository
    }

    /// Applies the invariant to freshly fetched incomplete tasks and
    /// persists any re-stamps. `frozen` (vacation or lapsed) means
    /// recurrence does not advance - occurrences stay put and nothing
    /// self-replenishes.
    func rollForward(
        _ tasks: [TaskItem],
        frozen: Bool = false,
        userId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> [TaskItem] {
        guard !frozen else { return tasks }
        var result: [TaskItem] = []
        result.reserveCapacity(tasks.count)
        for task in tasks {
            guard let rolled = Self.restamp(task, now: now, calendar: calendar) else {
                result.append(task)
                continue
            }
            if let newDueAt = rolled.task.dueAt {
                try? await taskRepository.rollForwardTask(
                    id: task.id,
                    to: newDueAt,
                    missedOccurrences: rolled.missed,
                    userId: userId
                )
            }
            result.append(rolled.task)
        }
        return result
    }

    /// The re-stamped task plus how many occurrences were missed, or nil
    /// when nothing rolls. The live occurrence becomes the most recent one
    /// already past its overdue boundary, so a neglected daily habit sits
    /// at under one day late forever instead of snowballing to "3 weeks
    /// overdue" (a category error for a habit).
    static func restamp(
        _ task: TaskItem,
        now: Date,
        calendar: Calendar = .current
    ) -> (task: TaskItem, missed: Int)? {
        guard !task.completed, let rule = task.repeatRule, task.dueAt != nil else { return nil }
        var current = task
        var missed = 0
        while let due = current.dueAt {
            // now == due asks for the single next occurrence, one step out.
            let next = rule.nextOccurrence(after: due, now: due, calendar: calendar)
            var probe = current
            probe.dueAt = next
            // The next occurrence "comes due" when it crosses its own
            // overdue boundary (the instant for timed tasks, end of local
            // day for date-only) - the same clock the mood engine reads.
            guard let boundary = MoodEngine.overdueBoundary(probe, calendar: calendar),
                  boundary <= now
            else { break }
            current = probe
            missed += 1
        }
        guard missed > 0 else { return nil }
        return (current, missed)
    }
}
