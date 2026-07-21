//
//  StreakMilestones.swift
//  MochiBuddy
//
//  Sparse streak celebrations (design doc: Cadence & celebration
//  constants): 7, 30, then every 50 days after 30. Sparse is the point -
//  the in-app day-1 delight carries the early upside, trophies stay rare
//  enough to mean something.
//

import Foundation

enum StreakMilestones {
    /// Remote-tunable, set once at launch.
    static var fixed = [7, 30]
    static var thenEvery = 50

    static func isMilestone(_ days: Int) -> Bool {
        if fixed.contains(days) { return true }
        guard let last = fixed.max(), days > last, thenEvery > 0 else { return false }
        return (days - last) % thenEvery == 0
    }

    /// The in-app celebration line for a landed milestone.
    static func celebrationText(days: Int) -> String {
        "\(days) days in a row! Mochi is so proud."
    }
}
