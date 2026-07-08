//
//  TaskItem.swift
//  MochiBuddy
//
//  Domain model for users/{uid}/tasks — deliberately lean (v1).
//

import Foundation

enum TaskPriority: String {
    case low
    case med
    case high
}

/// Repeat cadence (design doc v1 — custom intervals deferred). Completing
/// an occurrence spawns the next one.
enum TaskRepeat: String, CaseIterable {
    case daily
    case weekdays
    case weekly
    case monthly

    /// The next due date strictly after `now` — an overdue repeating task
    /// completed late skips the occurrences that already passed.
    func nextOccurrence(after due: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        var next = due
        repeat {
            next = step(from: next, calendar: calendar)
        } while next <= now
        return next
    }

    private func step(from date: Date, calendar: Calendar) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}

/// A task as it exists — the mood engine and every task surface read this.
struct TaskItem: Equatable, Identifiable {
    let id: String
    var title: String
    var notes: String?
    /// For `hasTime` tasks this is the instant; for date-only tasks it marks
    /// the calendar day (overdue flips at the end of that local day).
    var dueAt: Date?
    var hasTime: Bool
    var priority: TaskPriority
    var listId: String?
    var repeatRule: TaskRepeat?
    var completed: Bool
    var completedAt: Date?
    var createdAt: Date?
}

/// What the user provides when capturing a task.
struct TaskDraft {
    var title: String
    var notes: String?
    var dueAt: Date?
    var hasTime = false
    var priority: TaskPriority = .med
    var listId: String?
    var repeatRule: TaskRepeat?
}
