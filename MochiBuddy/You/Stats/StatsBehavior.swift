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

    /// The window every card below the streak strip reads. Day counts
    /// keep whole civil weeks so weekly bucketing stays clean.
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 months"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: 7
            case .month: 28
            case .threeMonths: 91
            }
        }

        /// Card eyebrow: "Last 7 days" / "Last 4 weeks" / "Last 3 months".
        var windowLabel: String {
            switch self {
            case .week: "Last 7 days"
            case .month: "Last 4 weeks"
            case .threeMonths: "Last 3 months"
            }
        }

        /// Card suffix: "Your rhythm · 4 weeks".
        var suffix: String {
            switch self {
            case .week: "7 days"
            case .month: "4 weeks"
            case .threeMonths: "3 months"
            }
        }
    }

    /// How the trend chart buckets its bars.
    enum TrendUnit: Equatable {
        case day
        case week
    }

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
        /// The selected window - defaults to the classic 4-week view.
        var range: TimeRange = .month
        var tiles: [StatTile] = []
        /// Trend points, oldest first. Daily for week/month, weekly buckets
        /// for 3 months. Empty until any completion exists.
        var trend: [TrendPoint] = []
        var trendUnit: TrendUnit = .day
        /// Caption under the trend - "82% on time · busiest on Tuesdays".
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
        case rangeChanged(TimeRange)
    }
}
