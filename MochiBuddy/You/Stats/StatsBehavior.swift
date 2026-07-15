//
//  StatsBehavior.swift
//  MochiBuddy
//

import SwiftUI

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

    /// One day in the 4-week completion trend (zero-filled).
    struct TrendPoint: Equatable, Identifiable {
        let id: Int
        let day: Date
        let count: Int
    }

    /// One list's share of the 4-week completions.
    struct ListSlice: Equatable, Identifiable {
        let id: String
        let name: String
        let color: Color
        let count: Int
    }

    struct UIState: UpdatableStruct, Equatable {
        var coins = 0
        var streakText = "0 days"
        var streakSub = "A task a day starts one"
        var week: [DayCell] = []
        var tiles: [StatTile] = []
        /// 28 daily points, oldest first.
        var trend: [TrendPoint] = []
        /// 4-week caption under the trend - "82% on time · busiest on Tuesdays".
        var trendCaption: String?
        var onTimeText = "–"
        var busiestWeekdayText = "–"
        var listBreakdown: [ListSlice] = []
    }

    enum ViewAction {
        case load
    }
}
