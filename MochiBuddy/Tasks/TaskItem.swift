//
//  TaskItem.swift
//  MochiBuddy
//
//  Domain model for users/{uid}/tasks - deliberately lean (v1).
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

    /// The next due date strictly after `now` - an overdue repeating task
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

/// The optional effort rating (ProjectDocs/build-notes/effort-implementation-guide.md). The user
/// only ever picks a magnitude label; each maps to a nominal duration and
/// the STORED value is the minutes (D1a) - the math stays independent of
/// label wording, and only these four values are ever written, so
/// minutes-to-label display is an exact lookup. The minutes are internal
/// nominals, never shown in the picker (D1).
enum EffortLevel: String, CaseIterable {
    case tiny
    case small
    case medium
    case large

    var minutes: Int {
        switch self {
        case .tiny: 15
        case .small: 30
        case .medium: 60
        case .large: 120
        }
    }

    var label: String {
        switch self {
        case .tiny: "Tiny"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Exact reverse lookup - the pill and Stats read the stored minutes
    /// back into a label. Unknown values (hand-edited docs) read as nil.
    init?(minutes: Int) {
        guard let level = Self.allCases.first(where: { $0.minutes == minutes }) else {
            return nil
        }
        self = level
    }
}

/// Momentum weights per level (D3), Remote Config tunable. Unset is never
/// penalized (D4): an unsized task keeps exactly weight 1, so honestly
/// sizing a small task is a no-op on mood and honesty stays free.
enum EffortConstants {
    static var tinyWeight = 1.0
    static var smallWeight = 1.4
    static var mediumWeight = 2.0
    static var largeWeight = 3.0

    static func weight(_ level: EffortLevel) -> Double {
        switch level {
        case .tiny: tinyWeight
        case .small: smallWeight
        case .medium: mediumWeight
        case .large: largeWeight
        }
    }

    /// The weight a stored minutes value earns toward momentum. nil or an
    /// unknown value is weight 1 - unknown, never penalized (D4).
    static func weight(estimatedMinutes: Int?) -> Double {
        guard let minutes = estimatedMinutes, let level = EffortLevel(minutes: minutes) else {
            return 1
        }
        return weight(level)
    }
}

/// A task as it exists - the mood engine and every task surface read this.
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
    /// Stable across a recurring task's occurrences: the first occurrence's
    /// id, inherited by every spawn (Personal Layer, Feature 4 - lets the
    /// comeback diversity gate see one habit as one identity). Nil on the
    /// first occurrence and on one-off tasks.
    var seriesId: String? = nil
    /// Times the user has pushed this task's due date later (snooze or an
    /// editor move to a later day). nil = unknown (never treated as 0;
    /// 0 means known-unmoved) - matches `CompletedTaskStat.rescheduleCount`.
    var rescheduleCount: Int? = nil
    /// Nominal minutes behind the chosen EffortLevel; nil = unrated (D2).
    var estimatedMinutes: Int? = nil
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
    /// Set only when spawning the next occurrence of a recurring task.
    var seriesId: String? = nil
    /// Nominal minutes behind the chosen EffortLevel; nil = unrated (D2).
    var estimatedMinutes: Int? = nil
}
