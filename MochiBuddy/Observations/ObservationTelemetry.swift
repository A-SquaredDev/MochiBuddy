//
//  ObservationTelemetry.swift
//  MochiBuddy
//
//  Instrumentation for the observation engine (Personal Layer, Feature 4).
//  observation_evaluated is the denominator: without it, "rarely shown"
//  can't be told apart from "rarely qualifies" vs "always loses beat
//  priority" vs "capped". At most once per type per user-day (the ledger
//  throttles). NEITHER event ever carries a conclusion payload - not the
//  weekday, not the band, not the listId (locked). os_log now; Firebase
//  Analytics drops in behind the same protocol later.
//

import Foundation
import os

enum ObservationTelemetryEvent {
    /// Coarse buckets only - never exact counts, never a conclusion.
    case evaluated(kind: ObservationKind, qualified: Bool, evidenceBucket: String, marginBucket: String)
    case shown(kind: ObservationKind, surface: String, confidenceBucket: String)
}

protocol ObservationTelemetry: AnyObject {
    func log(_ event: ObservationTelemetryEvent)
}

final class OSLogObservationTelemetry: ObservationTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "observations")

    func log(_ event: ObservationTelemetryEvent) {
        switch event {
        case .evaluated(let kind, let qualified, let evidence, let margin):
            logger.info("observation_evaluated type=\(kind.rawValue, privacy: .public) qualified=\(qualified) evidence=\(evidence, privacy: .public) margin=\(margin, privacy: .public)")
        case .shown(let kind, let surface, let confidence):
            logger.info("observation_shown type=\(kind.rawValue, privacy: .public) surface=\(surface, privacy: .public) confidence=\(confidence, privacy: .public)")
        }
    }
}

enum ObservationTelemetryBuckets {

    /// Coarse evidence volume, from the type's floor gate.
    static func evidence(_ count: Int) -> String {
        switch count {
        case ..<5: "0-4"
        case ..<10: "5-9"
        case ..<20: "10-19"
        case ..<40: "20-39"
        default: "40+"
        }
    }

    /// Coarse margin achievement: how decisively the top beat the rest.
    static func margin(topShare: Double?) -> String {
        guard let topShare else { return "none" }
        return switch topShare {
        case ..<0.3: "low"
        case ..<0.5: "mid"
        default: "high"
        }
    }
}
