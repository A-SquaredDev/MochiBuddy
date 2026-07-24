//
//  ObservationTypes.swift
//  MochiBuddy
//
//  The observation engine's vocabulary (Personal Layer, Feature 4).
//
//  The candidate/qualified split is a locked decision: ObservationCandidate
//  exists for the inspector and tests (it carries gate-by-gate evidence,
//  including failures); QualifiedObservation is the ONLY type production
//  surfaces accept, so a future UI caller cannot accidentally render a
//  failed candidate - the compiler refuses.
//

import Foundation

enum ObservationKind: String, CaseIterable {
    case weekday
    case timeOfDay
    case momentum
    case listReturn
    case comeback
}

/// The four copy bands - derived VIEWS over canonical minutes, never the
/// stored representation. Band boundaries are presentation decisions.
enum TimeOfDayBand: String, CaseIterable {
    case morning     // 05:00-12:00
    case afternoon   // 12:00-17:00
    case evening     // 17:00-21:00
    case night       // 21:00-05:00

    init(minute: Int) {
        switch minute {
        case 300..<720: self = .morning
        case 720..<1020: self = .afternoon
        case 1020..<1260: self = .evening
        default: self = .night
        }
    }
}

/// What a qualified observation concludes. Payloads never leave the device
/// and never reach telemetry (locked).
enum ObservationConclusion: Equatable, Hashable {
    /// Calendar weekday numbering, 1 = Sunday ... 7 = Saturday.
    case weekday(Int)
    case band(TimeOfDayBand)
    /// Rising only - a falling trend is silence, never a concerned line.
    case momentumRising
    case listReturn(listId: String)
    case comeback
}

/// One gate's evaluation, for the inspector and tests - achieved vs
/// required, human-readable.
struct ObservationGateCheck: Equatable {
    let name: String
    let achieved: String
    let required: String
    let passed: Bool
}

/// Inspector + tests ONLY. Carries the full gate story, pass or fail.
/// Production surfaces cannot accept this type.
struct ObservationCandidate: Equatable {
    let kind: ObservationKind
    /// The best conclusion this snapshot could support, present even when
    /// gates failed (so the inspector can show what ALMOST qualified);
    /// nil when there is no data to conclude anything from.
    let conclusion: ObservationConclusion?
    let gates: [ObservationGateCheck]
    /// Structured evidence volume for telemetry's coarse buckets - the
    /// count behind the type's floor gate.
    let evidenceCount: Int
    /// Top share achieved, for types with a share gate; nil otherwise.
    let topShare: Double?

    var passesAllGates: Bool {
        conclusion != nil && gates.allSatisfy(\.passed)
    }
}

/// The only type production surfaces accept. Constructed by the engine
/// exclusively - a stable conclusion that survived its type's policy.
struct QualifiedObservation: Equatable {
    let kind: ObservationKind
    let conclusion: ObservationConclusion
    /// Civil date (YYYY-MM-DD) the conclusion has held since, from the
    /// deterministic replay. For event/compose-time types, the day it fired.
    let stableSince: String
}

/// Feature 5's contract: canonical minutes with explicit provenance, so a
/// caller can never mistake a global fallback for list-scoped evidence.
struct DistributionResult: Equatable {

    enum Scope: Equatable {
        case list(String)
        case globalFallback
    }

    /// Canonical minute-of-day values (0...1439), day-capped, one entry
    /// per contributing completion. Histograms and bands are derived views.
    let minutes: [Int]
    let scopeUsed: Scope
    /// Day-capped completion count backing the minutes.
    let evidenceCount: Int
    let distinctDates: Int
}

// MARK: - Replay timeline (inspector + tests)

/// One day of the deterministic hysteresis replay - makes flapping visible.
struct ObservationReplayDay: Equatable {
    let day: String
    let passing: ObservationConclusion?
    let incumbent: ObservationConclusion?
    let incumbentFailStreak: Int
}

struct ObservationReplayTimeline: Equatable {
    let kind: ObservationKind
    let days: [ObservationReplayDay]
    let incumbent: ObservationConclusion?
    /// First day of the streak that made the incumbent stick.
    let stableSince: String?
}
