//
//  RundownRanker.swift
//  MochiBuddy
//
//  The morning rundown's "top 1-3" ranking (design doc: Morning rundown):
//  overdue by lateness descending, then due-today-with-time by time, then
//  due-today-date-only by priority. Evaluated at the rundown's own fire
//  time with recurrence rolled forward, so a briefing laid tonight ranks
//  tomorrow's world, not tonight's.
//

import Foundation

enum RundownRanker {

    static let limit = 3

    struct Ranking: Equatable {
        /// The capped top handful, in briefing order.
        var top: [TaskItem]
        /// The true overdue + due-today count before the cap - copy that
        /// says "5 things today" reads this, never top.count.
        var totalDue: Int
    }

    static func topTasks(
        from tasks: [TaskItem],
        at fireAt: Date,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        ranking(from: tasks, at: fireAt, calendar: calendar).top
    }

    static func ranking(
        from tasks: [TaskItem],
        at fireAt: Date,
        calendar: Calendar = .current
    ) -> Ranking {
        let world = tasks
            .filter { !$0.completed }
            .map { RecurrenceRoller.restamp($0, now: fireAt, calendar: calendar)?.task ?? $0 }

        let overdue = world
            .filter { (MoodEngine.hoursOverdue($0, now: fireAt, calendar: calendar) ?? 0) > 0 }
            .sorted { ($0.dueAt ?? fireAt) < ($1.dueAt ?? fireAt) } // earliest due = most late

        let dueToday = world.filter { task in
            guard let dueAt = task.dueAt else { return false }
            return calendar.isDate(dueAt, inSameDayAs: fireAt)
                && (MoodEngine.hoursOverdue(task, now: fireAt, calendar: calendar) ?? 0) <= 0
        }
        let timedToday = dueToday
            .filter(\.hasTime)
            .sorted { ($0.dueAt ?? fireAt) < ($1.dueAt ?? fireAt) }
        let dateOnlyToday = dueToday
            .filter { !$0.hasTime }
            .sorted { priorityRank($0.priority) > priorityRank($1.priority) }

        let ranked = overdue + timedToday + dateOnlyToday
        return Ranking(top: Array(ranked.prefix(limit)), totalDue: ranked.count)
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .low: 0
        case .med: 1
        case .high: 2
        }
    }
}
