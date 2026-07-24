//
//  Letter.swift
//  MochiBuddy
//
//  A letter is an immutable artifact of a closed period, composed exactly
//  once (Personal Layer, Feature 3). Everything inside is a snapshot:
//  task deletion, rename, or a pet rename never edits the postcard.
//  `readAt` is the ONE mutable field, synced so a letter read on the
//  phone doesn't re-flag on the iPad.
//

import Foundation

enum LetterClassification: String, CaseIterable {
    case great
    case steady
    case quiet
    case rough
    case vacationPartial
}

enum LetterBeatType: String, CaseIterable {
    // Optional beats, by priority.
    case milestone
    case comeback
    case bestDay
    case observation
    case listReturn
    // Structural beats - inserted first, never displaced.
    case presence
    case vacation
    case quiet
    // The rough letter's only permitted second beat: a small true
    // positive with no quantities, titles, or asks.
    case smallTruePositive
}

struct Letter: Equatable, Identifiable {
    /// `letter-{periodStart}` - the period's Monday as a plain date.
    let id: String
    // The period contract, pinned - no later ambiguity about coverage.
    let periodStart: Date
    let periodEndExclusive: Date
    let timeZoneId: String
    let classification: LetterClassification
    // Rotation + payload-free debugging.
    let beatTypes: [LetterBeatType]
    let lineIds: [String]
    // Both share variants, composed together at creation - the private
    // variant comes from structured beat data, never string surgery.
    let fullRenderedText: String
    let privateRenderedText: String
    /// Drives the signature and share card forever; renames never touch it.
    let petNameSnapshot: String
    let composedAt: Date
    // Provenance.
    let composerVersion: Int
    let copyDeckVersion: Int
    let periodSummaryHash: String
    /// The one mutable field.
    var readAt: Date?

    var isUnread: Bool { readAt == nil }

    /// Rough letters share only as private - full is never offered.
    var offersFullShareVariant: Bool { classification != .rough }
}
