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
    static func isMilestone(_ days: Int) -> Bool {
        if days == 7 || days == 30 { return true }
        return days > 30 && (days - 30) % 50 == 0
    }
}
