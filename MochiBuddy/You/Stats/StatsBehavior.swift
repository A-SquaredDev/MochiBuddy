//
//  StatsBehavior.swift
//  MochiBuddy
//

import Foundation

enum StatsBehavior {

    /// One day cell in the week strip. Level 0–3 drives the heat color.
    struct DayCell: Equatable, Identifiable {
        let id: Int
        let dayLetter: String
        let count: Int
        let level: Int
    }

    struct StatTile: Equatable, Identifiable {
        let id: String
        let value: String
        let title: String
        let subtitle: String
    }

    struct UIState: UpdatableStruct, Equatable {
        var coins = 0
        var streakText = "0 days"
        var streakSub = "A task a day starts one"
        var week: [DayCell] = []
        var tiles: [StatTile] = []
    }

    enum ViewAction {
        case load
    }
}
