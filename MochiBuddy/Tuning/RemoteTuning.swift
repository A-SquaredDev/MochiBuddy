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

        /// The seconds the planner actually spaces with.
        var spacing: TimeInterval { spacingHours * 3600 }
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
    // Observations (Personal Layer, Feature 4)
    var obsWindowDays = 42
    var obsReplayDays = 90
    var obsDayCap = 3
    var obsWeekdayMin = 15
    var obsWeekdayWeeks = 3
    var obsWeekdayShare = 0.30
    var obsTimeOfDayMin = 20
    var obsTimeOfDayDates = 5
    var obsTimeOfDayWeeks = 3
    var obsTimeOfDayShare = 0.40
    var obsMarginRatio = 1.5
    var obsTrendHalfMin = 10
    var obsTrendRatio = 1.3
    var obsTrendMinDelta = 0.2
    var obsTrendCooldownDays = 7
    var obsReturnQuietDays = 14
    var obsReturnHistoryMin = 5
    var obsComebackMin = 8
    var obsComebackDates = 3
    var obsComebackTasks = 3
    var obsComebackHours = 24.0
    var obsComebackP75Hours = 48.0
    var obsStickyDays = 14
    var obsRundownWeeklyCap = 2
    // Weekly letter (Personal Layer, Feature 3)
    var letterSendWeekday = 1
    var letterSendHour = 19
    var letterMaxBeats = 3
    var letterQuietMax = 2
    var letterRoughOverdueDays = 4
    var letterGreatRatio = 1.5

    static let defaults = ResolvedTuning()

    // MARK: - Derived intervals

    // The one place console hours/days become engine seconds - pure, so a
    // units mistake here fails a test instead of shipping silently.

    var shhDuration: TimeInterval { shhHours * 3600 }
    var recoveryHoldDuration: TimeInterval { recoveryHoldHours * 3600 }
    var backstopInterval: TimeInterval { TimeInterval(backstopDays) * 24 * 3600 }
    var vacationGraceDecay: TimeInterval { vacationGraceDecayHours * 3600 }

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

        // The re-entry wake target is DEFINED as the content anchor (doc:
        // Vacation mode → Constants, default = A). Track a tuned anchor
        // unless the console sets the wake explicitly - tuning the anchor
        // alone must never silently break "wake at ~content".
        tuning.vacationGraceWake = tuning.moodAnchor

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

        count("obs_window_days", 7...180, into: &tuning.obsWindowDays)
        count("obs_replay_days", 14...365, into: &tuning.obsReplayDays)
        count("obs_day_cap", 1...24, into: &tuning.obsDayCap)
        count("obs_weekday_min", 1...500, into: &tuning.obsWeekdayMin)
        count("obs_weekday_weeks", 1...26, into: &tuning.obsWeekdayWeeks)
        number("obs_weekday_share", 0...1, into: &tuning.obsWeekdayShare)
        count("obs_timeofday_min", 1...500, into: &tuning.obsTimeOfDayMin)
        count("obs_timeofday_dates", 1...100, into: &tuning.obsTimeOfDayDates)
        count("obs_timeofday_weeks", 1...26, into: &tuning.obsTimeOfDayWeeks)
        number("obs_timeofday_share", 0...1, into: &tuning.obsTimeOfDayShare)
        number("obs_margin_ratio", 1...10, into: &tuning.obsMarginRatio)
        count("obs_trend_half_min", 1...500, into: &tuning.obsTrendHalfMin)
        number("obs_trend_ratio", 1...10, into: &tuning.obsTrendRatio)
        number("obs_trend_min_delta", 0...10, into: &tuning.obsTrendMinDelta)
        count("obs_trend_cooldown_days", 1...60, into: &tuning.obsTrendCooldownDays)
        count("obs_return_quiet_days", 2...120, into: &tuning.obsReturnQuietDays)
        count("obs_return_history_min", 1...100, into: &tuning.obsReturnHistoryMin)
        count("obs_comeback_min", 1...100, into: &tuning.obsComebackMin)
        count("obs_comeback_dates", 1...50, into: &tuning.obsComebackDates)
        count("obs_comeback_tasks", 1...50, into: &tuning.obsComebackTasks)
        number("obs_comeback_hours", 1...336, into: &tuning.obsComebackHours)
        number("obs_comeback_p75_hours", 1...336, into: &tuning.obsComebackP75Hours)
        count("obs_sticky_days", 1...90, into: &tuning.obsStickyDays)
        count("obs_rundown_weekly_cap", 0...14, into: &tuning.obsRundownWeeklyCap)

        count("letter_send_weekday", 1...7, into: &tuning.letterSendWeekday)
        count("letter_send_hour", 0...23, into: &tuning.letterSendHour)
        count("letter_max_beats", 1...5, into: &tuning.letterMaxBeats)
        count("letter_quiet_max", 0...20, into: &tuning.letterQuietMax)
        count("letter_rough_overdue_days", 1...7, into: &tuning.letterRoughOverdueDays)
        number("letter_great_ratio", 1...10, into: &tuning.letterGreatRatio)
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
        "obs_window_days",
        "obs_replay_days",
        "obs_day_cap",
        "obs_weekday_min",
        "obs_weekday_weeks",
        "obs_weekday_share",
        "obs_timeofday_min",
        "obs_timeofday_dates",
        "obs_timeofday_weeks",
        "obs_timeofday_share",
        "obs_margin_ratio",
        "obs_trend_half_min",
        "obs_trend_ratio",
        "obs_trend_min_delta",
        "obs_trend_cooldown_days",
        "obs_return_quiet_days",
        "obs_return_history_min",
        "obs_comeback_min",
        "obs_comeback_dates",
        "obs_comeback_tasks",
        "obs_comeback_hours",
        "obs_comeback_p75_hours",
        "obs_sticky_days",
        "obs_rundown_weekly_cap",
        "letter_send_weekday",
        "letter_send_hour",
        "letter_max_beats",
        "letter_quiet_max",
        "letter_rough_overdue_days",
        "letter_great_ratio",
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
            .verySad: .init(count: tuning.cadenceVerySad.count, spacing: tuning.cadenceVerySad.spacing),
            .anxious: .init(count: tuning.cadenceAnxious.count, spacing: tuning.cadenceAnxious.spacing),
            .uneasy: .init(count: tuning.cadenceUneasy.count, spacing: tuning.cadenceUneasy.spacing),
        ]
        NotificationPlanner.Constants.backstopInterval = tuning.backstopInterval
        NotificationOrchestrator.Constants.horizonDays = tuning.horizonDays
        NotificationOrchestrator.Constants.shhDuration = tuning.shhDuration
        TaperTracker.recoveryHold = tuning.recoveryHoldDuration
        NotificationCopy.crushedYesterdayThreshold = tuning.crushedYesterdayThreshold

        VacationConstants.defaultDays = tuning.vacationDefaultDays
        VacationConstants.graceWake = tuning.vacationGraceWake
        VacationConstants.graceDecay = tuning.vacationGraceDecay
        VacationConstants.checkinDays = tuning.vacationCheckinDays
        VacationConstants.maxDays = tuning.vacationMaxDays

        RewardsStore.coinsPerTask = tuning.coinsPerTask
        StreakMilestones.fixed = tuning.streakMilestones.fixed
        StreakMilestones.thenEvery = tuning.streakMilestones.thenEvery

        // Observations: thresholds re-evaluate deterministically on the
        // next computation - stability is replayed, never stored, so no
        // ledger intervention accompanies a tuning change.
        ObservationConstants.windowDays = tuning.obsWindowDays
        ObservationConstants.replayDays = tuning.obsReplayDays
        ObservationConstants.dayCap = tuning.obsDayCap
        ObservationConstants.weekdayMin = tuning.obsWeekdayMin
        ObservationConstants.weekdayWeeks = tuning.obsWeekdayWeeks
        ObservationConstants.weekdayShare = tuning.obsWeekdayShare
        ObservationConstants.timeOfDayMin = tuning.obsTimeOfDayMin
        ObservationConstants.timeOfDayDates = tuning.obsTimeOfDayDates
        ObservationConstants.timeOfDayWeeks = tuning.obsTimeOfDayWeeks
        ObservationConstants.timeOfDayShare = tuning.obsTimeOfDayShare
        ObservationConstants.marginRatio = tuning.obsMarginRatio
        ObservationConstants.trendHalfMin = tuning.obsTrendHalfMin
        ObservationConstants.trendRatio = tuning.obsTrendRatio
        ObservationConstants.trendMinDelta = tuning.obsTrendMinDelta
        ObservationConstants.trendCooldownDays = tuning.obsTrendCooldownDays
        ObservationConstants.returnQuietDays = tuning.obsReturnQuietDays
        ObservationConstants.returnHistoryMin = tuning.obsReturnHistoryMin
        ObservationConstants.comebackMin = tuning.obsComebackMin
        ObservationConstants.comebackDates = tuning.obsComebackDates
        ObservationConstants.comebackTasks = tuning.obsComebackTasks
        ObservationConstants.comebackHours = tuning.obsComebackHours
        ObservationConstants.comebackP75Hours = tuning.obsComebackP75Hours
        ObservationConstants.stickyDays = tuning.obsStickyDays
        ObservationConstants.rundownWeeklyCap = tuning.obsRundownWeeklyCap

        // Letters: constants land at compose time and are baked into the
        // stored letter; a tuning pass changes future letters only.
        LetterConstants.sendWeekday = tuning.letterSendWeekday
        LetterConstants.sendHour = tuning.letterSendHour
        LetterConstants.maxBeats = tuning.letterMaxBeats
        LetterConstants.quietMax = tuning.letterQuietMax
        LetterConstants.roughOverdueDays = tuning.letterRoughOverdueDays
        LetterConstants.greatRatio = tuning.letterGreatRatio
    }

    /// Activate whatever last session fetched, apply it, then fetch in
    /// the background for next launch. The app awaits this BEFORE building
    /// AppContainer, so nothing ever computes on pre-apply values and
    /// mood(t) is deterministic for the whole session. Skipped entirely
    /// under tests so console tuning can never bend constant-pinned
    /// expectations.
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
