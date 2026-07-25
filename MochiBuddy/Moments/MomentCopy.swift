//
//  MomentCopy.swift
//  MochiBuddy
//
//  The moment copy deck - deliberately the ONLY Personal Layer deck with
//  zero rotation: racing writers deriving the same natural id must render
//  the same prose (create-only picks one winner; the content must not
//  depend on which). One template per event shape, rendered and frozen at
//  write time.
//

import Foundation

enum MomentCopy {

    static let deckVersion = 1

    /// Small numbers read warmer spelled out ("Seven days in a row");
    /// anything off the table stays a numeral rather than inventing
    /// English number grammar.
    private static let spelled: [Int: String] = [
        1: "One", 2: "Two", 3: "Three", 4: "Four", 5: "Five",
        6: "Six", 7: "Seven", 8: "Eight", 9: "Nine", 10: "Ten",
        30: "Thirty", 50: "Fifty", 100: "One hundred",
    ]

    private static func word(_ count: Int) -> String {
        spelled[count] ?? "\(count)"
    }

    /// Adoption with the name captured at the naming beat.
    static func adoption(petName: String) -> String {
        "You brought \(petName) home."
    }

    /// Backfilled or synthesized adoption - the name on that day is
    /// unknowable, so the line never implies one.
    static let adoptionLegacy = "The day your story began."

    static func anniversary(tier: AnniversaryTier) -> String {
        switch tier {
        case .week: "One week together."
        case .month: "One month together."
        case .year(let years):
            years == 1 ? "One year together." : "\(word(years)) years together."
        }
    }

    static func streakMilestone(count: Int, petName: String) -> String {
        "\(word(count)) days in a row with \(petName)."
    }

    static func vacationReturn(petName: String) -> String {
        "You and \(petName) picked back up."
    }

    static func listReturn(listName: String) -> String {
        "You found your way back to \(listName)."
    }

    /// The spoken variant appends the event's date so VoiceOver rows are
    /// self-contained without the visual timeline's date column.
    static func accessibilityText(rendered: String, occurredOn: String, locale: Locale) -> String {
        guard let spokenDate = AdoptedOnDate.displayString(occurredOn, locale: locale) else {
            return rendered
        }
        return "\(rendered) \(spokenDate)."
    }
}
