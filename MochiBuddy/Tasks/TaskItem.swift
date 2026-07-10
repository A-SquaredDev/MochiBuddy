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

/// Repeat cadence. Completing an occurrence spawns the next one.
enum TaskRepeat: Equatable {
    case daily
    case weekdays
    case weekly
    case monthly
    /// Specific days of the week (calendar numbering: 1 = Sunday … 7 = Saturday).
    case custom(Set<Int>)

    /// The fixed cadences offered as one-tap chips (custom is built in the editor).
    static let presets: [TaskRepeat] = [.daily, .weekdays, .weekly, .monthly]

    /// Wire format for users/{uid}/tasks.repeatRule.freq.
    var freq: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .custom: "custom"
        }
    }

    /// Sorted weekdays for a custom rule; nil for the fixed cadences.
    var customDays: [Int]? {
        if case .custom(let days) = self { return days.sorted() }
        return nil
    }

    init?(freq: String, days: [Int]? = nil) {
        switch freq {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        case "weekly": self = .weekly
        case "monthly": self = .monthly
        case "custom":
            let valid = Set((days ?? []).filter { (1...7).contains($0) })
            guard !valid.isEmpty else { return nil }
            self = .custom(valid)
        default: return nil
        }
    }

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
        case .custom(let days):
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            // An empty set can't come from init(freq:days:); cap at a week so
            // a bad value degrades to daily instead of spinning forever.
            var hops = 0
            while !days.contains(calendar.component(.weekday, from: next)), hops < 6 {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
                hops += 1
            }
            return next
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
