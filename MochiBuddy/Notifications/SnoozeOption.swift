//
//  SnoozeOption.swift
//  MochiBuddy
//
//  The reminder snooze menu (design doc: Actions & richness): 1h, tonight,
//  tomorrow. Pure date math so the targets are testable; the action
//  handler pushes the due date through the existing snooze path, which
//  also increments the procrastination counter.
//

import Foundation

enum SnoozeOption: String, CaseIterable {
    case oneHour = "snooze1h"
    case tonight = "snoozeTonight"
    case tomorrow = "snoozeTomorrow"

    /// Tonight means this evening hour; tomorrow means this morning hour.
    static let eveningHour = 19
    static let morningHour = 9

    var title: String {
        switch self {
        case .oneHour: "In 1 hour"
        case .tonight: "Tonight"
        case .tomorrow: "Tomorrow"
        }
    }

    func targetDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .tonight:
            let evening = calendar.date(
                bySettingHour: Self.eveningHour, minute: 0, second: 0, of: now
            ) ?? now.addingTimeInterval(3600)
            // Already evening: an hour out still reads as "tonight".
            return max(evening, now.addingTimeInterval(3600))
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(
                bySettingHour: Self.morningHour, minute: 0, second: 0, of: tomorrow
            ) ?? tomorrow
        }
    }
}
