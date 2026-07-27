//
//  SuggestionTypes.swift
//  MochiBuddy
//
//  The suggestion engine's vocabulary (Personal Layer, Feature 5).
//
//  SuggestionProposal is the ONLY type the chip UI accepts, and it names
//  its scope tier as a closed enum - reason copy takes the tier, so a
//  global fallback can never be explained as list- or task-specific
//  (provenance can't be misstated by construction). The evaluation's
//  gate story exists for the inspector and tests, failures included.
//

import Foundation

enum SuggestionTrigger: String, CaseIterable, Codable {
    /// Date set, no time chosen: "Mochi suggests 10:00 am."
    case newTime
    /// A recurring Mochi series completed persistently far from its due
    /// time: "This usually gets done around 8:00 pm."
    case reTime
}

enum SuggestionScopeTier: String, Codable {
    case series
    case list
    case global
    /// Weekday-filtered fallbacks (A1) - their own tier, so weekday-scoped
    /// answers get their own phrasing and can never borrow the pooled voice.
    case listWeekday
    case globalWeekday
}

/// A fully-formed suggestion - every gate and guardrail already passed.
struct SuggestionProposal: Equatable {
    let trigger: SuggestionTrigger
    let tier: SuggestionScopeTier
    /// Set for `.list` tier only - reason copy needs the list's name.
    let listId: String?
    /// UNROUNDED circular peak; re-time's mismatch was measured on this.
    let peakMinute: Int
    /// Friendly-rounded. Guardrails, ledger keys, and every rendered
    /// time use this and only this.
    let displayedMinute: Int
    /// Day-capped completions behind the winning scope (telemetry bucket).
    let evidenceCount: Int
    let isRecurring: Bool
    /// Calendar weekday (1 = Sunday) for the weekday-filtered tiers -
    /// their reason copy names the day. nil on pooled tiers.
    var weekday: Int? = nil

    /// Copy band of the displayed time (list/global reason phrasing).
    var band: TimeOfDayBand { TimeOfDayBand(minute: displayedMinute) }
}

/// Why an evaluation produced no chip - the coarse vocabulary that
/// suggestion_evaluated reports. Absence is always silent in the UI.
enum SuggestionBlockedReason: String {
    case evidence
    case peakShare
    case runnerUp
    case peakDates
    case bedtime
    case leadTime
    case apple
    case lapsed
    case dismissed
    case mismatch
}

/// One trigger's full evaluation: a proposal, or the reason there is
/// none - plus the gate-by-gate story for the inspector and tests.
struct SuggestionEvaluation: Equatable {
    let trigger: SuggestionTrigger
    let proposal: SuggestionProposal?
    /// nil iff `proposal` is non-nil.
    let blocked: SuggestionBlockedReason?
    let gates: [ObservationGateCheck]
}
