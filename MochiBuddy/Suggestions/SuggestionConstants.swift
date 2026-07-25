//
//  SuggestionConstants.swift
//  MochiBuddy
//
//  Every threshold the suggestion engine gates on (Personal Layer,
//  Feature 5). Remote-tunable via RemoteTuning, set once at launch.
//  Evidence qualifies on RAW day-capped counts - the reschedule weight
//  shapes an already-qualified peak, never manufactures qualification.
//
//  When unsure, no chip: every value here buys silence over a guess.
//

import Foundation

enum SuggestionConstants {
    /// General evidence floor (list + global scopes), day-capped completions.
    static var minEvidence = 15
    /// General distinct-date floor (list + global scopes).
    static var minDates = 5
    /// Primary window's share of the scope's day-capped completions.
    static var peakShare = 0.35
    /// Half-width of a candidate window, circular minutes around its center.
    static var peakWindowMin = 90
    /// Distinct dates required INSIDE the primary window - a cluster minted
    /// on two odd days fails even when the global date floor passes.
    static var peakDates = 3
    /// Primary share must beat the strongest window centered >= 3 circular
    /// hours away by this much. Bimodal means silence, by construction.
    static var runnerUpMargin = 0.10
    /// Series scope evidence floor (timed completions).
    static var seriesMin = 8
    /// Series scope distinct-date floor.
    static var seriesDates = 5
    /// List scope: distinct task/series identities required.
    static var listMinSeries = 3
    /// List scope: no single identity may exceed this share of the list's
    /// day-capped count - one daily habit can't speak for a whole list.
    static var listSeriesShare = 0.40
    /// Re-time fires only when the UNROUNDED series peak sits at least
    /// this many circular hours from the scheduled time.
    static var retimeMismatchHours = 3
    /// Today-due tasks: the rounded time must be at least this far in the
    /// future - silenced, never moved later.
    static var minLeadMin = 30
    /// A dismissal re-arms only after the DISPLAYED proposal moves this
    /// many circular minutes.
    static var dismissRearmMin = 60
    /// Peak-shaping weight per reschedule: 1 + min(count, 3) x this.
    static var rescheduleWeight = 0.25

    /// Bumped ONLY on semantic changes to what a dismissal or acceptance
    /// means - clears the ledger. Threshold tuning never touches it.
    static let schemaVersion = 1
}
