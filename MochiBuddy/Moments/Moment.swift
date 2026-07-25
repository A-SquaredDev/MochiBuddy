//
//  Moment.swift
//  MochiBuddy
//
//  A Journal moment (Personal Layer, Feature 6): a synced, create-only
//  document whose natural id identifies an EVENT, never merely its
//  category - a broken-and-rebuilt 30-day streak is a new moment, two
//  vacations ending on one date are two moments. Payloads are snapshots
//  derived from immutable event facts at write time, so racing writers
//  produce content-identical documents and the timeline never rewrites
//  (the postcard rule: prose keeps its original language and names).
//

import Foundation

enum MomentType: String, CaseIterable {
    case adoption
    case anniversary
    case streakMilestone
    case vacationReturn
    case listReturn

    /// The id prefix the security rules hold consistent with the declared
    /// type - create-only prevents edits, this prevents fabricated ids.
    var idPrefix: String {
        switch self {
        case .adoption: "adoption-"
        case .anniversary: "anniversary-"
        case .streakMilestone: "streak-milestone-"
        case .vacationReturn: "vacation-return-"
        case .listReturn: "list-return-"
        }
    }
}

struct Moment: Equatable, Identifiable {

    static let schemaVersion = 1

    /// Natural key - see the exhaustive v1 table in the spec. Identifies
    /// the event; create-only writes make concurrent creation idempotent.
    let id: String
    let type: MomentType
    /// Civil date (YYYY-MM-DD, `AdoptedOnDate` currency) rendered
    /// verbatim - stored dates never migrate between months when the
    /// device travels.
    let occurredOn: String
    let renderedTextSnapshot: String
    let accessibilityTextSnapshot: String
    /// The pet's name as of the event; nil when unknowable (a backfilled
    /// adoption never implies the current name was used then).
    let petNameSnapshot: String?
    /// e.g. the list's name as of a list-return event - renders unchanged
    /// after the list is renamed or deleted.
    let subjectNameSnapshot: String?
    let localeIdentifier: String
    let copyDeckVersion: Int
    /// Provenance link to the upstream event where one exists (the
    /// Feature 4 ledger's event key for list returns).
    let sourceEventId: String?
    let createdAt: Date
}
