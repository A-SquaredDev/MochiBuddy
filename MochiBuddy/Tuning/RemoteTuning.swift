//
//  RemoteTuning.swift
//  MochiBuddy
//
//  Remote Config wiring for every constant the design doc marks tunable.
//  Values are resolved once per launch (activate-on-next-launch), so
//  mood(t) stays deterministic for the whole session and the scheduled
//  pings can never disagree with a mid-flight tuning change; the fetch
//  that lands during this session applies on the next one.
//
//  Every value is clamped on the way in - a typo in the console degrades
//  to the shipped default, never to a broken invariant.
//

import FirebaseRemoteConfig
import Foundation

/// The seam under Firebase so resolution is pure and testable.
protocol TuningSource {
    /// A numeric parameter, nil when the console doesn't set it.
    func number(_ key: String) -> Double?
    /// A JSON-string parameter's data, nil when unset.
    func json(_ key: String) -> Data?
}

/// Every tunable, resolved and validated. `defaults` mirrors the shipped
/// constants exactly.
struct ResolvedTuning: Equatable {

    struct Cadence: Equatable, Codable {
        var count: Int
        var spacingHours: Double
    }

    struct Milestones: Equatable, Codable {
        var fixed: [Int]
        var thenEvery: Int
    }

    // Mood engine
    var moodAnchor = 58.0
    var moodLatenessCapHours = 48.0
    var moodBaseSting = 0.4
    var moodStressSaturation = 4.0
    var moodMomentumMax = 42.0
    var moodMomentumSaturation = 2.5
    var moodMomentumGate = 20.0
    // Notifications
    var moodPingsDailyCeiling = 4
    var floorTaper = [4, 3, 2, 1]
    var cadenceVerySad = Cadence(count: 4, spacingHours: 2)
    var cadenceAnxious = Cadence(count: 3, spacingHours: 3)
    var cadenceUneasy = Cadence(count: 1, spacingHours: 4)
    var backstopDays = 7
    var horizonDays = 7
    var shhHours = 24.0
    var recoveryHoldHours = 24.0
    var crushedYesterdayThreshold = 5
    // Vacation
    var vacationDefaultDays = 7
    var vacationGraceWake = 58.0
    var vacationGraceDecayHours = 24.0
    var vacationCheckinDays = 14
    var vacationMaxDays = 30
    // Rewards
    var coinsPerTask = 10
    var streakMilestones = Milestones(fixed: [7, 30], thenEvery: 50)

    static let defaults = ResolvedTuning()

    /// Read every parameter, keeping the default wherever the source is
    /// silent or the value fails validation.
    static func resolve(from source: TuningSource) -> ResolvedTuning {
        var tuning = ResolvedTuning()

        func number(_ key: String, _ range: ClosedRange<Double>, into value: inout Double) {
            if let raw = source.number(key), range.contains(raw) { value = raw }
        }
        func count(_ key: String, _ range: ClosedRange<Int>, into value: inout Int) {
            if let raw = source.number(key), let whole = Int(exactly: raw.rounded()),
               range.contains(whole) {
                value = whole
            }
        }
        func cadence(_ key: String, into value: inout Cadence) {
            guard let data = source.json(key),
                  let parsed = try? JSONDecoder().decode(Cadence.self, from: data),
                  (0...24).contains(parsed.count), parsed.spacingHours > 0
            else { return }
            value = parsed
        }

        number("mood_anchor", 1...99, into: &tuning.moodAnchor)
        number("mood_lateness_cap_hours", 1...720, into: &tuning.moodLatenessCapHours)
        number("mood_base_sting", 0...1, into: &tuning.moodBaseSting)
        number("mood_stress_saturation", 0.1...100, into: &tuning.moodStressSaturation)
        number("mood_momentum_max", 0...100, into: &tuning.moodMomentumMax)
        number("mood_momentum_saturation", 0.1...100, into: &tuning.moodMomentumSaturation)
        number("mood_momentum_gate", 0.1...100, into: &tuning.moodMomentumGate)

        count("notif_mood_pings_daily_ceiling", 0...24, into: &tuning.moodPingsDailyCeiling)
        if let data = source.json("notif_floor_taper"),
           let taper = try? JSONDecoder().decode([Int].self, from: data),
           !taper.isEmpty, taper.allSatisfy({ (0...24).contains($0) }) {
            tuning.floorTaper = taper
        }
        cadence("notif_cadence_very_sad", into: &tuning.cadenceVerySad)
        cadence("notif_cadence_anxious", into: &tuning.cadenceAnxious)
        cadence("notif_cadence_uneasy", into: &tuning.cadenceUneasy)
        count("notif_backstop_days", 1...60, into: &tuning.backstopDays)
        count("notif_horizon_days", 1...14, into: &tuning.horizonDays)
        number("notif_shh_hours", 1...168, into: &tuning.shhHours)
        number("notif_recovery_hold_hours", 1...168, into: &tuning.recoveryHoldHours)
        count("notif_crushed_yesterday_threshold", 1...50, into: &tuning.crushedYesterdayThreshold)

        count("vacation_default_days", 1...30, into: &tuning.vacationDefaultDays)
        number("vacation_grace_wake", 1...99, into: &tuning.vacationGraceWake)
        number("vacation_grace_decay_hours", 1...168, into: &tuning.vacationGraceDecayHours)
        count("vacation_checkin_days", 1...60, into: &tuning.vacationCheckinDays)
        count("vacation_max_days", 1...365, into: &tuning.vacationMaxDays)

        count("coins_per_task", 1...1000, into: &tuning.coinsPerTask)
        if let data = source.json("streak_milestones"),
           let parsed = try? JSONDecoder().decode(Milestones.self, from: data),
           !parsed.fixed.isEmpty, parsed.fixed.allSatisfy({ $0 > 0 }), parsed.thenEvery > 0 {
            tuning.streakMilestones = parsed
        }
        return tuning
    }
}

@MainActor
enum RemoteTuning {

    /// The canonical parameter set - must mirror the Firebase console
    /// exactly. Tests pin every entry to a resolved field, so a key can't
    /// drift silently on either side.
    static let numberKeys: [String] = [
        "mood_anchor",
        "mood_lateness_cap_hours",
        "mood_base_sting",
        "mood_stress_saturation",
        "mood_momentum_max",
        "mood_momentum_saturation",
        "mood_momentum_gate",
        "notif_mood_pings_daily_ceiling",
        "notif_backstop_days",
        "notif_horizon_days",
        "notif_shh_hours",
        "notif_recovery_hold_hours",
        "notif_crushed_yesterday_threshold",
        "vacation_default_days",
        "vacation_grace_wake",
        "vacation_grace_decay_hours",
        "vacation_checkin_days",
        "vacation_max_days",
        "coins_per_task",
    ]
    static let jsonKeys: [String] = [
        "notif_floor_taper",
        "notif_cadence_very_sad",
        "notif_cadence_anxious",
        "notif_cadence_uneasy",
        "streak_milestones",
    ]
    static var allKeys: [String] { numberKeys + jsonKeys }

    /// Push resolved values into the constants the engines read. Called
    /// once at launch before the first re-lay.
    static func apply(_ tuning: ResolvedTuning) {
        MoodEngine.Constants.anchor = tuning.moodAnchor
        MoodEngine.Constants.latenessCapHours = tuning.moodLatenessCapHours
        MoodEngine.Constants.base = tuning.moodBaseSting
        MoodEngine.Constants.stressSaturation = tuning.moodStressSaturation
        MoodEngine.Constants.momentumMax = tuning.moodMomentumMax
        MoodEngine.Constants.momentumSaturation = tuning.moodMomentumSaturation
        MoodEngine.Constants.gate = tuning.moodMomentumGate

        NotificationPlanner.Constants.moodPingsPerDayCeiling = tuning.moodPingsDailyCeiling
        NotificationPlanner.Constants.floorTaperBudgets = tuning.floorTaper
        NotificationPlanner.Constants.cadenceRules = [
            .verySad: .init(count: tuning.cadenceVerySad.count,
                            spacing: tuning.cadenceVerySad.spacingHours * 3600),
            .anxious: .init(count: tuning.cadenceAnxious.count,
                            spacing: tuning.cadenceAnxious.spacingHours * 3600),
            .uneasy: .init(count: tuning.cadenceUneasy.count,
                           spacing: tuning.cadenceUneasy.spacingHours * 3600),
        ]
        NotificationPlanner.Constants.backstopInterval = TimeInterval(tuning.backstopDays) * 24 * 3600
        NotificationOrchestrator.Constants.horizonDays = tuning.horizonDays
        NotificationOrchestrator.Constants.shhDuration = tuning.shhHours * 3600
        TaperTracker.recoveryHold = tuning.recoveryHoldHours * 3600
        NotificationCopy.crushedYesterdayThreshold = tuning.crushedYesterdayThreshold

        VacationConstants.defaultDays = tuning.vacationDefaultDays
        VacationConstants.graceWake = tuning.vacationGraceWake
        VacationConstants.graceDecay = tuning.vacationGraceDecayHours * 3600
        VacationConstants.checkinDays = tuning.vacationCheckinDays
        VacationConstants.maxDays = tuning.vacationMaxDays

        RewardsStore.coinsPerTask = tuning.coinsPerTask
        StreakMilestones.fixed = tuning.streakMilestones.fixed
        StreakMilestones.thenEvery = tuning.streakMilestones.thenEvery
    }

    /// Activate whatever last session fetched, apply it, then fetch in
    /// the background for next launch. Skipped entirely under tests so
    /// console tuning can never bend constant-pinned expectations.
    static func bootstrap() async {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let remoteConfig = RemoteConfig.remoteConfig()
        _ = try? await remoteConfig.activate()
        apply(ResolvedTuning.resolve(from: FirebaseTuningSource(remoteConfig: remoteConfig)))
        remoteConfig.fetch { _, _ in } // lands next launch
    }
}

/// Reads only values the console actually set - static/default sources
/// fall through to the shipped constants.
struct FirebaseTuningSource: TuningSource {
    let remoteConfig: RemoteConfig

    func number(_ key: String) -> Double? {
        let value = remoteConfig.configValue(forKey: key)
        guard value.source == .remote else { return nil }
        return value.numberValue.doubleValue
    }

    func json(_ key: String) -> Data? {
        let value = remoteConfig.configValue(forKey: key)
        guard value.source == .remote, !value.dataValue.isEmpty else { return nil }
        return value.dataValue
    }
}
