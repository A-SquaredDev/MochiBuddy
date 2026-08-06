//
//  JournalBehavior.swift
//  MochiBuddy
//
//  The Journal tab (Personal Layer, Feature 6) - deliberately only a
//  container: letters and moments the other features already produced,
//  the gated observation card, and a data footer that records activity
//  without judging it. Record vs. grade is the line: no coins, no on-time
//  percentage, no ungated busiest-weekday - asserted by tests over this
//  state surface.
//

import Foundation

enum JournalBehavior {

    /// The newest unread letter, promoted - a presentation state of a
    /// timeline row, never a second copy (it is excluded from the rows
    /// below while promoted).
    struct HeroLetter: Equatable {
        let letterId: String
        let excerpt: String
        let dateLabel: String
    }

    struct LetterRow: Equatable {
        let letterId: String
        let dateLabel: String
        let excerpt: String
        let isUnread: Bool
    }

    struct MomentRow: Equatable {
        let momentId: String
        let text: String
        let dateLabel: String
        /// SF Symbol for the tile.
        let icon: String
        /// The adoption row earns the origin treatment (filled rail dot).
        let isOrigin: Bool
    }

    enum TimelineRow: Equatable, Identifiable {
        case letter(LetterRow)
        case moment(MomentRow)

        var id: String {
            switch self {
            case .letter(let row): "letter-row-\(row.letterId)"
            case .moment(let row): row.momentId
            }
        }
    }

    struct MonthGroup: Equatable, Identifiable {
        /// "2026-07" - from STORED dates, never the device zone.
        let id: String
        /// "July", or "July 2025" outside the current year.
        let title: String
        let rows: [TimelineRow]
    }

    struct DayCell: Equatable, Identifiable {
        let id: Int
        let dayLetter: String
        let count: Int
        let level: Int
    }

    struct TrendPoint: Equatable, Identifiable {
        let id: Int
        let day: Date
        let count: Int
    }

    /// The record footer. `bestStreak` nil and `trend` empty mean those
    /// rows are omitted - absent, never placeholdered.
    struct Footer: Equatable {
        let title: String
        let week: [DayCell]
        let doneLabel: String
        let doneCount: Int
        let bestStreak: Int?
        let trend: [TrendPoint]
    }

    /// Day-one presentation: the adoption moment as a centered beat plus
    /// the forward-looking line (accurate to Feature 3's gating).
    struct YoungState: Equatable {
        let adoptionText: String
        /// "July 23, 2026" - rendered from the stored date verbatim.
        let dateLabel: String
    }

    struct UIState: UpdatableStruct, Equatable {
        var isLoading = true
        var petName = PetNameSanitizer.defaultName
        /// "With Mochi since June" / "Mochi is napping · paused" - nil in
        /// the young state.
        var headerSubtitle: String?
        var isLapsed = false
        var young: YoungState?
        var hero: HeroLetter?
        var months: [MonthGroup] = []
        /// Rendered observation lines - empty removes the card entirely.
        var noticedLines: [String] = []
        var footer: Footer?
    }

    enum ViewAction {
        case load
        case heroTapped
        case letterTapped(String)
        case sectionVisible(JournalSection)
        /// A pending envelope/notification route landed while visible.
        case consumePendingRoute
    }

    enum NavigationEvent {
        case openLetter(Letter, LetterOpenSource)
    }
}

enum JournalSection: String {
    case timeline
    case observations
    case data
}
