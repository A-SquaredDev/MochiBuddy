//
//  PersonalLayerPlannerTests.swift
//  MochiBuddyTests
//
//  The canonical rundown priority (streak milestone > anniversary >
//  crushed yesterday > callback > observation), the same-date collision
//  rule, the deterministic callback selection contract, and
//  only-the-winner-consumes cadence across a laid horizon.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct PersonalLayerPlannerTests {

    private func day(_ string: String) -> CivilDay { CivilDay(string)! }

    private func context(
        _ dateString: String,
        register: RundownEmotionalRegister = .open,
        crushed: Bool = false,
        deferred: AnniversaryMilestone? = nil,
        streakClaimed: Bool = false
    ) -> PersonalLayerPlanner.DayContext {
        let civil = day(dateString)
        return PersonalLayerPlanner.DayContext(
            day: civil,
            fireAt: Date(timeIntervalSince1970: TimeInterval(civil.dayNumber) * 86_400 + 7 * 3600),
            register: register,
            crushedYesterday: crushed,
            deferredAcknowledgment: deferred,
            streakClaimed: streakClaimed
        )
    }

    /// Miner inputs with one qualifying best day well in the past.
    private func minerWithBestDay(
        adoptedOn: String = "2026-01-01", bestDayDate: String = "2026-06-15"
    ) -> CallbackMinerInputs {
        CallbackMinerInputs(
            records: (0..<5).map { index in
                makeStat(taskId: "t\(index)", localDate: bestDayDate, localMinute: 540 + index)
            },
            adoptedOn: adoptedOn
        )
    }

    private func assign(
        _ days: [PersonalLayerPlanner.DayContext],
        miner: CallbackMinerInputs,
        observations: [QualifiedObservation] = [],
        ledger: CallbackLedger.State = CallbackLedger.State(),
        canSurfaceObservation: Bool = true
    ) -> [PersonalLayerPlanner.Assignment] {
        PersonalLayerPlanner.assign(
            days: days, miner: miner, observations: observations, ledger: ledger,
            canSurfaceObservation: { _, _ in canSurfaceObservation }
        )
    }

    // MARK: - The priority table (table-driven, streak first)

    @Test func priorityTable() {
        let anniversaryDay = "2026-07-08" // adoptedOn 2026-07-01 + 7
        let miner = CallbackMinerInputs(adoptedOn: "2026-07-01")
        let deferred = AnniversaryMilestone(tier: .month, day: day("2026-07-01"))
        let observation = QualifiedObservation(
            kind: .weekday, conclusion: .weekday(3), stableSince: "2026-07-01"
        )

        // Streak claim beats everything - and renders NOTHING (in-app
        // celebration owns the day; edge case 1).
        let claimed = assign(
            [context(anniversaryDay, crushed: true, deferred: deferred, streakClaimed: true)],
            miner: miner, observations: [observation]
        )
        #expect(claimed.isEmpty)

        // Anniversary beats crushed yesterday, callbacks, observations.
        let anniversary = assign(
            [context(anniversaryDay, crushed: true)],
            miner: minerWithBestDay(adoptedOn: "2026-07-01"), observations: [observation]
        )
        #expect(anniversary.count == 1)
        if case .anniversary(let milestone) = anniversary[0].line {
            #expect(milestone.tier == .week)
        } else {
            Issue.record("expected the anniversary line, got \(anniversary[0].line)")
        }

        // Deferred acknowledgment rides the anniversary slot on a
        // non-milestone day, above crushed.
        let ack = assign(
            [context("2026-07-04", crushed: true, deferred: deferred)], miner: miner
        )
        #expect(ack.first?.line == .deferredAnniversary(deferred))

        // Crushed beats a qualified callback.
        let crushed = assign(
            [context("2026-07-30", crushed: true)], miner: minerWithBestDay()
        )
        #expect(crushed.first?.line == .crushedYesterday)

        // Callback beats observation.
        let callback = assign(
            [context("2026-07-30")], miner: minerWithBestDay(), observations: [observation]
        )
        if case .callback(let fact) = callback.first?.line {
            #expect(fact.type == .bestDay)
        } else {
            Issue.record("expected a callback, got \(String(describing: callback.first?.line))")
        }

        // Observation is the last tier standing.
        let obs = assign(
            [context("2026-07-30")], miner: CallbackMinerInputs(adoptedOn: "2026-01-01"),
            observations: [observation]
        )
        #expect(obs.first?.line == .observation(observation))

        // And an empty day carries nothing at all.
        #expect(assign([context("2026-07-30")], miner: miner).isEmpty)
    }

    @Test func streakClaimDetection() {
        // Reachable today: streak 6 continuing, day 7 would be a
        // milestone.
        #expect(PersonalLayerPlanner.streakClaims(
            day: day("2026-07-08"), streakCount: 6, lastActiveDay: day("2026-07-07")
        ))
        // Already reached today.
        #expect(PersonalLayerPlanner.streakClaims(
            day: day("2026-07-08"), streakCount: 7, lastActiveDay: day("2026-07-08")
        ))
        // Adjacent-day case (edge case 2): day 7 landed YESTERDAY - no
        // claim today, both anniversaries and streaks surface on their
        // own days.
        #expect(!PersonalLayerPlanner.streakClaims(
            day: day("2026-07-08"), streakCount: 7, lastActiveDay: day("2026-07-07")
        ))
        // A broken streak claims nothing (completing today restarts at 1).
        #expect(!PersonalLayerPlanner.streakClaims(
            day: day("2026-07-08"), streakCount: 6, lastActiveDay: day("2026-07-01")
        ))
    }

    // MARK: - Register gate at the slot

    @Test func registerGatesCallbackTypes() {
        // Below content, recovery is the only candidate: a best day
        // yields nothing under recoveryOnly...
        let blocked = assign([context("2026-07-30", register: .recoveryOnly)], miner: minerWithBestDay())
        #expect(blocked.isEmpty)
        // ...and closed admits nothing, while the anniversary still
        // shows (edge case 10: a date is not a demand).
        let closedAnniversary = assign(
            [context("2026-07-08", register: .closed)],
            miner: minerWithBestDay(adoptedOn: "2026-07-01")
        )
        if case .anniversary = closedAnniversary.first?.line {} else {
            Issue.record("anniversary must ignore the register")
        }
    }

    // MARK: - Selection contract

    @Test func typePriorityDateEchoFirst() {
        // A day that is both a month-echo of a qualifying day AND has an
        // older best day: echo wins (it expires today, best day can wait).
        var miner = minerWithBestDay(bestDayDate: "2026-05-20")
        miner.records += (0..<5).map { index in
            makeStat(taskId: "e\(index)", localDate: "2026-06-30", localMinute: 540 + index)
        }
        let result = assign([context("2026-07-30")], miner: miner)
        if case .callback(let fact) = result.first?.line {
            #expect(fact.type == .dateEcho)
            #expect(fact.factId == "completion-day-2026-06-30")
        } else {
            Issue.record("expected the date echo")
        }
    }

    @Test func onlyTheWinnerConsumesAndCapsThreadAcrossTheHorizon() {
        // Two DISTINCT facts: a unique-max best day (six completions on
        // Jun 10) and an echo source (five on Jun 13). Four laid
        // mornings. The min gap 3 must hold ACROSS the horizon: days 1
        // and 4 get callbacks, days 2-3 blocked by the gap.
        var miner = CallbackMinerInputs(
            records: (0..<6).map { index in
                makeStat(taskId: "b\(index)", localDate: "2026-06-10", localMinute: 540 + index)
            },
            adoptedOn: "2026-01-01"
        )
        miner.records += (0..<5).map { index in
            makeStat(taskId: "e\(index)", localDate: "2026-06-13", localMinute: 540 + index)
        }
        // Mon Jul 13 is an echo of Jun 13; Jul 14-16 are plain days.
        let days = ["2026-07-13", "2026-07-14", "2026-07-15", "2026-07-16"].map { context($0) }
        let result = assign(days, miner: miner)

        let byDate = Dictionary(uniqueKeysWithValues: result.map { ($0.day.dateString, $0.line) })
        // Day 1: the echo (expires that day, top priority).
        if case .callback(let first)? = byDate["2026-07-13"] {
            #expect(first.type == .dateEcho)
        } else {
            Issue.record("expected an echo on the 13th")
        }
        // Days 2-3: inside the min gap - nothing.
        #expect(byDate["2026-07-14"] == nil)
        #expect(byDate["2026-07-15"] == nil)
        // Day 4: gap satisfied, the best day tells.
        if case .callback(let fourth)? = byDate["2026-07-16"] {
            #expect(fourth.type == .bestDay)
        } else {
            Issue.record("expected the best day on the 16th")
        }
    }

    @Test func onceUntilChangedAndCrossTypeDedup() {
        var ledger = CallbackLedger.State()
        // The best day was already told (as either type - shared id).
        ledger.toldFacts["completion-day-2026-06-15"] = "2026-07-01"
        let result = assign([context("2026-07-30")], miner: minerWithBestDay(), ledger: ledger)
        #expect(result.isEmpty)

        // A NEW best day date is a new fact: eligible again.
        let changed = assign(
            [context("2026-07-30")],
            miner: minerWithBestDay(bestDayDate: "2026-07-10"),
            ledger: ledger
        )
        #expect(changed.count == 1)
    }

    @Test func losingDateEchoExpiresSilently() {
        // The echo loses its one date to crushed-yesterday; the best day
        // stays fully eligible later, the echo never comes back.
        var miner = minerWithBestDay(bestDayDate: "2026-05-20")
        miner.records += (0..<5).map { index in
            makeStat(taskId: "e\(index)", localDate: "2026-06-30", localMinute: 540 + index)
        }
        let days = [
            context("2026-07-30", crushed: true),   // echo date, lost to crushed
            context("2026-08-02"),                   // past the gap? no callback yet told
        ]
        let result = assign(days, miner: miner)
        #expect(result.first?.line == .crushedYesterday)
        if case .callback(let later)? = result.last?.line {
            // The echo expired with its date; the best day tells instead.
            #expect(later.type == .bestDay)
        } else {
            Issue.record("expected the best day after the lost echo")
        }
    }

    @Test func determinismSameInputsSameAssignment() {
        var miner = minerWithBestDay()
        miner.records += (0..<5).map { index in
            makeStat(taskId: "e\(index)", localDate: "2026-06-30", localMinute: 540 + index)
        }
        let days = ["2026-07-28", "2026-07-30", "2026-08-03"].map { context($0) }
        let first = assign(days, miner: miner)
        let second = assign(days, miner: miner)
        #expect(first == second)
    }

    @Test func observationSameWeekOnlyOnce() {
        let observation = QualifiedObservation(
            kind: .weekday, conclusion: .weekday(3), stableSince: "2026-07-01"
        )
        // Two mornings in one ISO week: the planner itself holds the
        // line to one observation even when the ledger closure says yes.
        let days = [context("2026-07-28"), context("2026-07-29")]
        let result = assign(days, miner: CallbackMinerInputs(adoptedOn: "2026-01-01"), observations: [observation])
        #expect(result.count == 1)
    }
}
