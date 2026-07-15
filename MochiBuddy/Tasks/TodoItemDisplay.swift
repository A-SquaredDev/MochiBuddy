//
//  TodoItemDisplay.swift
//  MochiBuddy
//
//  The one place task fields become row copy (meta/state/chip) - shared by
//  Home, the Tasks tab, and ListDetail so the three surfaces never drift.
//  Field-based (not TaskItem-based) so Apple-Reminders-backed rows can use
//  the same rules.
//

import SwiftUI

enum TodoItemDisplay {

    struct RowDisplay {
        let meta: String
        let state: TodoRowState
        let chip: String
    }

    static func row(for task: TaskItem, now: Date) -> RowDisplay {
        row(
            completed: task.completed,
            completedAt: task.completedAt,
            dueAt: task.dueAt,
            hasTime: task.hasTime,
            priority: task.priority,
            now: now
        )
    }

    /// `priority: nil` (external rows) never earns the "High" chip.
    static func row(
        completed: Bool,
        completedAt: Date?,
        dueAt: Date?,
        hasTime: Bool,
        priority: TaskPriority?,
        now: Date
    ) -> RowDisplay {
        let calendar = Calendar.current
        let state: TodoRowState
        let meta: String

        if completed {
            state = .done
            meta = "Done · \(doneText(completedAt, calendar: calendar))"
        } else if let hours = hoursOverdue(dueAt: dueAt, hasTime: hasTime, now: now), hours > 0 {
            state = .overdue
            meta = "⏰ Overdue by \(overdueText(hours: hours))"
        } else if let dueAt {
            let timeText = dueAt.formatted(date: .omitted, time: .shortened)
            if calendar.isDate(dueAt, inSameDayAs: now) {
                if hasTime, dueAt.timeIntervalSince(now) < 3 * 3600 {
                    state = .due
                    meta = "Due soon · \(timeText)"
                } else {
                    state = .normal
                    meta = hasTime ? "Due today · \(timeText)" : "Due later today"
                }
            } else {
                state = .normal
                // Within the next week a weekday is unambiguous; beyond it,
                // show the real date - otherwise completing a recurring task
                // ahead of time ("Fri" → next "Fri") reads as a no-op.
                let offset = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: dueAt)
                ).day ?? 0
                let dayText = offset <= 6
                    ? dueAt.formatted(.dateTime.weekday(.abbreviated))
                    : dueAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                meta = hasTime ? "\(dayText) · \(timeText)" : "\(dayText) · all day"
            }
        } else {
            state = .normal
            meta = "Anytime"
        }

        let chip = switch state {
        case .done: "Done"
        case .due: "Soon"
        case .overdue, .normal: priority == .high ? "High" : "Focus"
        }

        return RowDisplay(meta: meta, state: state, chip: chip)
    }

    /// Resolves a task's list into its row indicator. Inbox (nil listId)
    /// gets none - default rows stay calm.
    static func listTag(for listId: String?, in lists: [TaskList]) -> (name: String, color: Color)? {
        guard let listId, let list = lists.first(where: { $0.id == listId }) else { return nil }
        return (list.name, Color(hexString: list.colorHex))
    }

    // Same boundary rule as MoodEngine.overdueBoundary - date-only tasks
    // become overdue at the following midnight.
    private static func hoursOverdue(dueAt: Date?, hasTime: Bool, now: Date) -> Double? {
        guard let dueAt else { return nil }
        let boundary: Date
        if hasTime {
            boundary = dueAt
        } else {
            let startOfDay = Calendar.current.startOfDay(for: dueAt)
            boundary = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? dueAt
        }
        return now.timeIntervalSince(boundary) / 3600
    }

    private static func doneText(_ completedAt: Date?, calendar: Calendar) -> String {
        guard let completedAt else { return "nice one" }
        if calendar.isDateInToday(completedAt) {
            return completedAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(completedAt) { return "yesterday" }
        return completedAt.formatted(.dateTime.day().month(.abbreviated))
    }

    private static func overdueText(hours: Double) -> String {
        if hours < 1 { return "a moment" }
        if hours < 24 { return "\(Int(hours)) hr" }
        let days = Int(hours / 24)
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}
