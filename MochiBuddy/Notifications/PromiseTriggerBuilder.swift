//
//  PromiseTriggerBuilder.swift
//  MochiBuddy
//
//  A recurring task's promise can ride ONE repeating calendar trigger
//  (the design doc's notification bonus: an infinite daily habit costs
//  one slot forever). Only cadences expressible as a single component
//  pattern repeat; the rest schedule their next occurrence and lean on
//  the re-lay to refresh - correct either way, one is just cheaper.
//

import Foundation

enum PromiseTriggerBuilder {

    /// Repeating date components for a rule, or nil when the cadence
    /// can't repeat in one trigger (weekdays / custom day sets).
    static func repeatingComponents(
        for rule: TaskRepeat,
        dueAt: Date,
        calendar: Calendar = .current
    ) -> DateComponents? {
        let time = calendar.dateComponents([.hour, .minute], from: dueAt)
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        switch rule {
        case .daily:
            return components
        case .weekly:
            components.weekday = calendar.component(.weekday, from: dueAt)
            return components
        case .monthly:
            // Days 29-31 do not exist in every month, and a repeating
            // day-31 calendar trigger silently skips the short ones.
            // Those cadences schedule their single next occurrence
            // (nextOccurrence clamps via byAdding: .month) and lean on
            // the re-lay, like weekdays and custom sets.
            let day = calendar.component(.day, from: dueAt)
            guard day <= 28 else { return nil }
            components.day = day
            return components
        case .weekdays, .custom:
            return nil
        }
    }
}
