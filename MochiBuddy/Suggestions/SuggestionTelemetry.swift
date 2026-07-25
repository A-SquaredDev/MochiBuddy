//
//  SuggestionTelemetry.swift
//  MochiBuddy
//
//  Instrumentation for suggested times (Personal Layer, Feature 5) - the
//  layer's ACTIONABILITY validator. suggestion_evaluated is the
//  denominator (once per trigger per editor session where the trigger's
//  preconditions held); suggestion_outcome classifies once, at save;
//  matched is always its own component (round times match by chance).
//  No payloads ever: no times, no titles, no ids, no lateness values.
//  os_log now; Firebase Analytics drops in behind the same protocol.
//

import Foundation
import os

enum SuggestionOutcome: String {
    /// Tapped, saved the exact proposed time - the primary validator.
    case accepted
    /// Tapped, changed, saved - partial influence.
    case adjusted
    /// Never tapped; saved a manual time within +-30 circular minutes -
    /// supporting evidence with a known chance component.
    case matched
    /// Dismissed and did not later match.
    case dismissed
    /// Saved with none of the above.
    case ignored
}

enum SuggestionTelemetryEvent {
    case evaluated(trigger: SuggestionTrigger, qualified: Bool, blockedReason: String)
    case shown(trigger: SuggestionTrigger, tier: SuggestionScopeTier, evidenceBucket: String, recurring: Bool)
    case outcome(trigger: SuggestionTrigger, tier: SuggestionScopeTier, outcome: SuggestionOutcome)
    /// Coarse device-computed downstream signal: did the accepted time
    /// survive, and did a later completion land near it?
    case retention(trigger: SuggestionTrigger, tier: SuggestionScopeTier, bucket: String)
}

protocol SuggestionTelemetry: AnyObject {
    func log(_ event: SuggestionTelemetryEvent)
}

final class OSLogSuggestionTelemetry: SuggestionTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "suggestions")

    func log(_ event: SuggestionTelemetryEvent) {
        switch event {
        case .evaluated(let trigger, let qualified, let reason):
            logger.info("suggestion_evaluated trigger=\(trigger.rawValue, privacy: .public) qualified=\(qualified) reason=\(reason, privacy: .public)")
        case .shown(let trigger, let tier, let evidence, let recurring):
            logger.info("suggestion_shown trigger=\(trigger.rawValue, privacy: .public) scope=\(tier.rawValue, privacy: .public) evidence=\(evidence, privacy: .public) recurring=\(recurring)")
        case .outcome(let trigger, let tier, let outcome):
            logger.info("suggestion_outcome trigger=\(trigger.rawValue, privacy: .public) scope=\(tier.rawValue, privacy: .public) outcome=\(outcome.rawValue, privacy: .public)")
        case .retention(let trigger, let tier, let bucket):
            logger.info("suggestion_retention trigger=\(trigger.rawValue, privacy: .public) scope=\(tier.rawValue, privacy: .public) bucket=\(bucket, privacy: .public)")
        }
    }
}
