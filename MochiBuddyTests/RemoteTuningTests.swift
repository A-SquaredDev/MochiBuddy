//
//  RemoteTuningTests.swift
//  MochiBuddyTests
//
//  Resolution is pure: shipped defaults when the console is silent,
//  overrides when it speaks, and defaults again when it speaks nonsense -
//  a console typo must never break a tested invariant. apply() itself is
//  only smoke-tested with default-identical values, because the constants
//  are process-global and the suite runs in parallel.
//

import FirebaseRemoteConfig
import Foundation
import Testing
@testable import MochiBuddy

private struct StubTuningSource: TuningSource {
    var numbers: [String: Double] = [:]
    var jsons: [String: String] = [:]

    func number(_ key: String) -> Double? { numbers[key] }
    func json(_ key: String) -> Data? { jsons[key]?.data(using: .utf8) }
}

@Suite("RemoteTuning · resolution")
struct RemoteTuningTests {

    @Test("a silent console resolves to exactly the shipped defaults")
    func silentConsoleIsDefaults() {
        #expect(ResolvedTuning.resolve(from: StubTuningSource()) == .defaults)
    }

    @Test("set parameters override: numbers, arrays, cadence, and milestones")
    func overridesApply() {
        let source = StubTuningSource(
            numbers: [
                "mood_anchor": 62,
                "notif_mood_pings_daily_ceiling": 3,
                "vacation_max_days": 21,
                "coins_per_task": 15,
                "notif_shh_hours": 48,
            ],
            jsons: [
                "notif_floor_taper": "[3,2,1]",
                "notif_cadence_very_sad": #"{"count":3,"spacingHours":2.5}"#,
                "streak_milestones": #"{"fixed":[5,20],"thenEvery":25}"#,
            ]
        )
        let tuning = ResolvedTuning.resolve(from: source)

        #expect(tuning.moodAnchor == 62)
        #expect(tuning.moodPingsDailyCeiling == 3)
        #expect(tuning.vacationMaxDays == 21)
        #expect(tuning.coinsPerTask == 15)
        #expect(tuning.shhHours == 48)
        #expect(tuning.floorTaper == [3, 2, 1])
        #expect(tuning.cadenceVerySad == .init(count: 3, spacingHours: 2.5))
        #expect(tuning.streakMilestones == .init(fixed: [5, 20], thenEvery: 25))
        // Untouched parameters keep their defaults.
        #expect(tuning.moodBaseSting == ResolvedTuning.defaults.moodBaseSting)
        #expect(tuning.cadenceAnxious == ResolvedTuning.defaults.cadenceAnxious)
    }

    @Test("out-of-range and malformed values fall back to the shipped defaults")
    func nonsenseClampsToDefaults() {
        let source = StubTuningSource(
            numbers: [
                "mood_anchor": 250,                       // outside 1...99
                "notif_mood_pings_daily_ceiling": -2,     // negative
                "mood_base_sting": 7,                     // outside 0...1
                "vacation_max_days": 0,                   // zero
            ],
            jsons: [
                "notif_floor_taper": "[]",                // empty
                "notif_cadence_very_sad": "not json",
                "streak_milestones": #"{"fixed":[],"thenEvery":50}"#,
            ]
        )
        #expect(ResolvedTuning.resolve(from: source) == .defaults,
                "every bad value must degrade to the default, never to zero")
    }

    @Test("the canonical key set matches the published console parameters, one to one")
    @MainActor
    func consoleKeysMatch() {
        // The exact list published in the Firebase console on Jul 19 2026.
        let published: Set<String> = [
            "mood_anchor", "mood_lateness_cap_hours", "mood_base_sting",
            "mood_stress_saturation", "mood_momentum_max", "mood_momentum_saturation",
            "mood_momentum_gate",
            "notif_mood_pings_daily_ceiling", "notif_floor_taper",
            "notif_cadence_very_sad", "notif_cadence_anxious", "notif_cadence_uneasy",
            "notif_backstop_days", "notif_horizon_days", "notif_shh_hours",
            "notif_recovery_hold_hours", "notif_crushed_yesterday_threshold",
            "vacation_default_days", "vacation_grace_wake", "vacation_grace_decay_hours",
            "vacation_checkin_days", "vacation_max_days",
            "coins_per_task", "streak_milestones",
        ]
        #expect(Set(RemoteTuning.allKeys) == published)
        #expect(RemoteTuning.allKeys.count == 24, "no duplicates")
    }

    @Test("EVERY published key is consumed with its declared type - override all 24, every field moves")
    @MainActor
    func everyKeyDecodes() {
        let source = StubTuningSource(
            numbers: [
                "mood_anchor": 60,
                "mood_lateness_cap_hours": 72,
                "mood_base_sting": 0.5,
                "mood_stress_saturation": 5,
                "mood_momentum_max": 40,
                "mood_momentum_saturation": 3,
                "mood_momentum_gate": 25,
                "notif_mood_pings_daily_ceiling": 5,
                "notif_backstop_days": 10,
                "notif_horizon_days": 8,
                "notif_shh_hours": 12,
                "notif_recovery_hold_hours": 36,
                "notif_crushed_yesterday_threshold": 6,
                "vacation_default_days": 5,
                "vacation_grace_wake": 60,
                "vacation_grace_decay_hours": 12,
                "vacation_checkin_days": 10,
                "vacation_max_days": 21,
                "coins_per_task": 12,
            ],
            jsons: [
                "notif_floor_taper": "[5,4,3,2,1]",
                "notif_cadence_very_sad": #"{"count":5,"spacingHours":1.5}"#,
                "notif_cadence_anxious": #"{"count":2,"spacingHours":4}"#,
                "notif_cadence_uneasy": #"{"count":2,"spacingHours":6}"#,
                "streak_milestones": #"{"fixed":[10],"thenEvery":30}"#,
            ]
        )
        // Coverage guard: the stub sets exactly the canonical key set.
        #expect(Set(source.numbers.keys) == Set(RemoteTuning.numberKeys))
        #expect(Set(source.jsons.keys) == Set(RemoteTuning.jsonKeys))

        let tuning = ResolvedTuning.resolve(from: source)
        let expected = ResolvedTuning(
            moodAnchor: 60, moodLatenessCapHours: 72, moodBaseSting: 0.5,
            moodStressSaturation: 5, moodMomentumMax: 40, moodMomentumSaturation: 3,
            moodMomentumGate: 25,
            moodPingsDailyCeiling: 5, floorTaper: [5, 4, 3, 2, 1],
            cadenceVerySad: .init(count: 5, spacingHours: 1.5),
            cadenceAnxious: .init(count: 2, spacingHours: 4),
            cadenceUneasy: .init(count: 2, spacingHours: 6),
            backstopDays: 10, horizonDays: 8, shhHours: 12,
            recoveryHoldHours: 36, crushedYesterdayThreshold: 6,
            vacationDefaultDays: 5, vacationGraceWake: 60,
            vacationGraceDecayHours: 12, vacationCheckinDays: 10, vacationMaxDays: 21,
            coinsPerTask: 12,
            streakMilestones: .init(fixed: [10], thenEvery: 30)
        )
        #expect(tuning == expected, "every parameter must land in exactly one field")
    }

    @Test("the Firebase source ignores values the console never set")
    func firebaseSourceFiltersUnsetKeys() {
        // Deterministic without network: the test process never fetches or
        // activates, so an unknown key reports a static (unset) source.
        let source = FirebaseTuningSource(remoteConfig: .remoteConfig())
        #expect(source.number("definitely_not_a_real_key") == nil)
        #expect(source.json("also_not_a_real_key") == nil)
    }

    @Test("applying default-identical values is observably a no-op")
    @MainActor
    func applyDefaultsSmoke() {
        RemoteTuning.apply(.defaults)
        #expect(MoodEngine.Constants.anchor == 58)
        #expect(NotificationPlanner.Constants.floorTaperBudgets == [4, 3, 2, 1])
        #expect(NotificationPlanner.Constants.cadence(for: .verySad, level: .balanced).count == 4)
        #expect(VacationConstants.maxDays == 30)
        #expect(RewardsStore.coinsPerTask == 10)
        #expect(StreakMilestones.isMilestone(80))
    }
}
