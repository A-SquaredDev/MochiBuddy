//
//  MoodEngine.swift
//  MochiBuddy
//
//  The mood baseline — a pure, deterministic function of task state
//  (mochi-design-doc.md "Mood algorithm"). Volume ≠ stress: only overdue
//  tasks contribute; completions add momentum, gated so you can't fake
//  happiness while behind. Runs on-device and offline.
//

import Foundation

enum MoodEngine {

    /// Tuning constants from the design doc (Remote Config candidates).
    enum Constants {
        /// Content anchor — the mood with nothing due and nothing done.
        static let anchor: Double = 58
        /// Lateness saturates after this many hours overdue.
        static let latenessCapHours: Double = 48
        /// Instant sting the moment a task goes overdue.
        static let base: Double = 0.4
        static let stressSaturation: Double = 4
        static let momentumMax: Double = 42
        static let momentumSaturation: Double = 2.5
        /// Momentum is suppressed while stress is high.
        static let gate: Double = 20
        static let bufferCap: Double = 30
    }

    /// Baseline mood 0–100. Pets/treats never touch this — see ComfortBuffer.
    static func baseline(
        incompleteTasks: [TaskItem],
        completionsLast24h: Int,
        vacationMode: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        // Vacation mode suppresses stress accrual entirely.
        let stress: Double
        if vacationMode {
            stress = 0
        } else {
            let load = incompleteTasks.reduce(0.0) { sum, task in
                guard let hours = hoursOverdue(task, now: now, calendar: calendar), hours > 0 else {
                    return sum
                }
                let lateness = min(1, hours / Constants.latenessCapHours)
                return sum + weight(task.priority) * (Constants.base + (1 - Constants.base) * lateness)
            }
            stress = Constants.anchor * (1 - exp(-load / Constants.stressSaturation))
        }

        let momentum = Constants.momentumMax
            * (1 - exp(-Double(completionsLast24h) / Constants.momentumSaturation))
        let gate = min(1, max(0, 1 - stress / Constants.gate))

        return min(100, max(0, Constants.anchor - stress + momentum * gate))
    }

    /// Hours past the task's overdue boundary, or nil when it has no due date.
    /// Timed tasks flip at their instant; date-only tasks at end of local day.
    static func hoursOverdue(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> Double? {
        guard let boundary = overdueBoundary(task, calendar: calendar) else { return nil }
        return now.timeIntervalSince(boundary) / 3600
    }

    static func overdueBoundary(_ task: TaskItem, calendar: Calendar = .current) -> Date? {
        guard let dueAt = task.dueAt else { return nil }
        guard !task.hasTime else { return dueAt }
        let startOfDay = calendar.startOfDay(for: dueAt)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? dueAt
    }

    /// Priority IS the mood weight (design doc: low 1 / med 1.5 / high 2).
    static func weight(_ priority: TaskPriority) -> Double {
        switch priority {
        case .low: 1
        case .med: 1.5
        case .high: 2
        }
    }
}
