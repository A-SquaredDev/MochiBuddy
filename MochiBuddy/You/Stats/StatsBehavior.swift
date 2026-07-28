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

    /// One hourly bar of the "Your best hours" histogram; id is the axis
    /// bucket index (0 = the 5a bucket, D3's axis origin).
    struct HourBar: Equatable, Identifiable {
        let id: Int
        let count: Int
        let inPeak: Bool
    }

    /// "Your best hours" - histogram, the C1 tile pair, and the state-
    /// generated Mochi caption. nil until any completion exists (D1).
    struct BestHoursCard: Equatable {
        let bars: [HourBar]
        /// "10a to 1p" - the highlighted 3-hour window as a range.
        let peakText: String
        /// "55%" - the peak window's share, same ±90 window as the
        /// suggestion engine (D10).
        let inWindowText: String
        let caption: String
    }

    /// One weekday's own hour curve (the day picker, comp turn 3): the
    /// card's middle swaps to this while a day is selected. The tiles are
    /// nil below the D5 evidence floor - bars show, tiles claim, and the
    /// claim waits for evidence.
    struct DayDetail: Equatable {
        /// Calendar weekday, 1 = Sunday ... 7 = Saturday.
        let weekday: Int
        let bars: [HourBar]
        let peakText: String?
        let inWindowText: String?
        let caption: String
    }

    /// One "Day by day" weekday row. All positions are fractions of the
    /// shared 5a-to-5a axis; a thin row carries only the typical dot (D4).
    struct WeekdayRowUI: Equatable, Identifiable {
        let id: Int
        let label: String
        let first: Double?
        let last: Double?
        let q1: Double?
        let q3: Double?
        let typical: Double?
        /// "10:50a" right-hand label, from the typical dot.
        let timeText: String?
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
        /// Caption under the trend - "82% on time".
        var trendCaption: String?
        /// "Your best hours" - shows whenever there is data (D1).
        var bestHours: BestHoursCard?
        /// "Day by day" rows - empty until a row qualifies, and always
        /// empty on the Week range (D6).
        var dayByDay: [WeekdayRowUI] = []
        /// Card 2's Mochi line (thin days / full read); nil when hidden.
        var dayByDayCaption: String?
        /// The day picker's selection; nil = "All days" (the seven rows).
        var selectedDay: Int?
        /// The selected day's curve - non-nil only while a day is picked.
        var dayDetail: DayDetail?
        var listBreakdown: [ListSlice] = []
        /// Qualified observation lines in the pet's voice, rendered
        /// read-only (the Journal owns live surfacing bookkeeping).
        var noticedLines: [String] = []
        var memoryRows: [MemoryRow] = []
    }

    enum ViewAction {
        case load
        case rangeChanged(TimeRange)
        /// Day picker + row taps; nil returns to "All days".
        case selectDay(Int?)
    }
}
