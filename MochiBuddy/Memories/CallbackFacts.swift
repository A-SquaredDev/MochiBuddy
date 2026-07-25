//
//  CallbackFacts.swift
//  MochiBuddy
//
//  The memory-callback vocabulary (Personal Layer, Feature 2). A fact is
//  a concrete past win the data can prove; its identity is a canonical
//  factId, independent of callback type, so the same completion day can
//  never reappear as "best day" and again as "date echo". A fact is told
//  once - until its identity materially changes.
//

import Foundation

enum CallbackType: String, CaseIterable, Codable {
    case dateEcho
    case recovery
    case bestDay
    case streakEra

    /// Selection priority: date echo expires today and cannot wait;
    /// recovery is the most emotionally useful; streak era is the most
    /// static and can always wait. Lower = first.
    var priority: Int {
        switch self {
        case .dateEcho: 0
        case .recovery: 1
        case .bestDay: 2
        case .streakEra: 3
        }
    }
}

struct CallbackFact: Equatable {
    let type: CallbackType
    /// Canonical cross-type identity - the once-until-changed key.
    let factId: String
    /// The civil day the memory is about: recency ordering + coarse
    /// relative time in copy.
    let sourceDay: CivilDay

    /// Best day + date echo: that day's completion count (counts are
    /// permitted in these two families, never in recovery).
    var count: Int = 0
    /// Best day: the max was shared - copy says "one of your biggest
    /// days", never a false superlative.
    var tied: Bool = false
    /// Streak era: the record count.
    var streakCount: Int = 0
    /// Streak era: era phrasing allowed only when bestStreakAchievedOn
    /// exists - legacy records get count-only copy, never a guessed date.
    var eraDated: Bool = false
    /// Date echo: whole calendar months back to the remembered day.
    var monthsBack: Int = 0
}

/// Canonical factId constructors - the one place identities are minted.
enum CallbackFactID {
    static func completionDay(_ day: CivilDay) -> String {
        "completion-day-\(day.dateString)"
    }

    static func recovery(contributingKeys: [String], windowStart: CivilDay) -> String {
        let payload = contributingKeys.sorted().joined(separator: "|") + "|" + windowStart.dateString
        return "recovery-\(String(format: "%08x", fnv1a(payload)))"
    }

    static func streakRecord(count: Int, achievedOn: String?) -> String {
        "streak-record-\(count)-\(achievedOn ?? "legacy")"
    }

    /// True for ids that consume callback cadence (vs the planner's
    /// non-callback assignment markers).
    static func isCallbackFactId(_ id: String) -> Bool {
        id.hasPrefix("completion-day-") || id.hasPrefix("recovery-") || id.hasPrefix("streak-record-")
    }

    /// FNV-1a, same stable-hash doctrine as the letter composer - never
    /// String.hashValue (process-seeded).
    static func fnv1a(_ string: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

/// Why a callback type produced nothing this day - the coarse blocked
/// reason `callback_evaluated` carries (never a payload). Without the
/// denominator, "callbacks are scarce" can't be told apart from healthy
/// sparsity, tight floors, or priority starvation.
enum CallbackBlockedReason: String {
    case relationshipAge
    case noFact
    case evidence
    case factAge
    case register
    case priority
    case gap
    case weeklyCap
    case alreadyTold
}

/// One type's evaluation on one day - the miner's full answer, so the
/// telemetry denominator and the dev inspector share one truth.
struct CallbackEvaluation: Equatable {
    let type: CallbackType
    /// The qualifying fact, floors applied. Nil when blocked.
    let fact: CallbackFact?
    /// The first gate that failed, mining-level only; the planner adds
    /// selection-level reasons (register / priority / gap / cap / told).
    let blocked: CallbackBlockedReason?
}
