//
//  StatsBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum StatsBehavior {

    /// The week strip and trend share the Journal's derivations - one
    /// bucketing rule for both surfaces.
    typealias DayCell = JournalBehavior.DayCell
    typealias TrendPoint = JournalBehavior.TrendPoint

    struct StatTile: Equatable, Identifiable {
        let id: String
        let value: String
        let title: String
        let subtitle: String
    }

    /// One time-of-day band's share of the 4-week completions.
    struct BandBar: Equatable, Identifiable {
        let id: String
        let label: String
        let count: Int
    }

    /// One list's share of the 4-week completions.
    struct ListSlice: Equatable, Identifiable {
        let id: String
        let name: String
        let color: Color
        let count: Int
    }

    /// One mined memory - a concrete past win the data can prove.
    struct MemoryRow: Equatable, Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
    }

    struct UIState: UpdatableStruct, Equatable {
        var petName = "Mochi"
        var coins = 0
        var streakText = "0 days"
        var streakSub = "A task a day starts one"
        var week: [DayCell] = []
        var tiles: [StatTile] = []
        /// 28 daily points, oldest first. Empty until any completion exists.
        var trend: [TrendPoint] = []
        /// 4-week caption under the trend - "82% on time · busiest on Tuesdays".
        var trendCaption: String?
        /// Morning/afternoon/evening/night, fixed order, zero-filled.
        var rhythm: [BandBar] = []
        var rhythmCaption: String?
        var listBreakdown: [ListSlice] = []
        /// Qualified observation lines in the pet's voice, rendered
        /// read-only (the Journal owns live surfacing bookkeeping).
        var noticedLines: [String] = []
        var memoryRows: [MemoryRow] = []
    }

    enum ViewAction {
        case load
    }
}
