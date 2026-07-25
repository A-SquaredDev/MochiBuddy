//
//  CallbackFactMinerTests.swift
//  MochiBuddyTests
//
//  Feature 2 fact mining: evidence floors (incl. distinct identities and
//  recovery's >= 24h-overdue qualification), fact-age floors, the
//  relationship-age activation, tie rules, canonical fact identity, and
//  the bestStreakAchievedOn-driven streak-era gates. Fixtures satisfy
//  the shipped defaults - process-global constants are never mutated.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct CallbackFactMinerTests {

    private func day(_ string: String) -> CivilDay { CivilDay(string)! }

    /// A qualifying best day: five one-off completions, five identities.
    private func bigDay(_ localDate: String, count: Int = 5) -> [CompletedTaskStat] {
        (0..<count).map { index in
            makeStat(taskId: "\(localDate)-t\(index)", localDate: localDate, localMinute: 540 + index)
        }
    }

    private func inputs(
        records: [CompletedTaskStat],
        adoptedOn: String = "2026-01-01",
        streak: Int = 0,
        best: Int = 0,
        achievedOn: String? = nil,
        lastActive: String? = nil
    ) -> CallbackMinerInputs {
        CallbackMinerInputs(
            records: records,
            adoptedOn: adoptedOn,
            streakCount: streak,
            bestStreakCount: best,
            bestStreakAchievedOn: achievedOn,
            lastActiveDay: lastActive.map { day($0) }
        )
    }

    private func evaluation(
        _ type: CallbackType, _ inputs: CallbackMinerInputs, on evalDay: CivilDay
    ) -> CallbackEvaluation {
        CallbackFactMiner.evaluate(inputs, on: evalDay).first { $0.type == type }!
    }

    // MARK: - Relationship activation

    @Test func relationshipYoungerThan21DaysBlocksEverything() {
        let miner = inputs(records: bigDay("2026-07-01"), adoptedOn: "2026-06-20")
        let evaluations = CallbackFactMiner.evaluate(miner, on: day("2026-07-08"))
        #expect(evaluations.count == CallbackType.allCases.count)
        #expect(evaluations.allSatisfy { $0.fact == nil && $0.blocked == .relationshipAge })
        // Day 21 exactly activates.
        let active = CallbackFactMiner.evaluate(miner, on: day("2026-07-11"))
        #expect(active.contains { $0.fact != nil })
    }

    // MARK: - Best day

    @Test func bestDayNeedsCountAndDistinctIdentities() {
        // Five completions but only two identities (a recurring habit
        // hammered thrice shares one seriesId): floor fails.
        let sameSeries = (0..<3).map { index in
            makeStat(taskId: "occ\(index)", seriesId: "habit", localDate: "2026-07-01", localMinute: 500 + index)
        }
        let twoMore = (0..<2).map { index in
            makeStat(taskId: "solo\(index)", localDate: "2026-07-01", localMinute: 700 + index)
        }
        let blocked = evaluation(.bestDay, inputs(records: sameSeries + twoMore), on: day("2026-07-20"))
        #expect(blocked.fact == nil)
        #expect(blocked.blocked == .evidence)

        let qualified = evaluation(.bestDay, inputs(records: bigDay("2026-07-01")), on: day("2026-07-20"))
        #expect(qualified.fact?.factId == "completion-day-2026-07-01")
        #expect(qualified.fact?.count == 5)
        #expect(qualified.fact?.tied == false)
    }

    @Test func tiedMaxPicksLatestDayAndFlagsTie() {
        let records = bigDay("2026-06-10") + bigDay("2026-07-01")
        let fact = evaluation(.bestDay, inputs(records: records), on: day("2026-07-20")).fact
        #expect(fact?.sourceDay == day("2026-07-01"))
        #expect(fact?.tied == true)
        // A strictly bigger day is the unique standout.
        let bigger = records + bigDay("2026-06-20", count: 7)
        let unique = evaluation(.bestDay, inputs(records: bigger), on: day("2026-07-20")).fact
        #expect(unique?.sourceDay == day("2026-06-20"))
        #expect(unique?.tied == false)
    }

    @Test func factAgeFloorBlocksFreshMemories() {
        // Day 21 of the relationship, best day was yesterday: no memory
        // yet (edge case 13).
        let miner = inputs(records: bigDay("2026-07-10"), adoptedOn: "2026-06-20")
        let blocked = evaluation(.bestDay, miner, on: day("2026-07-11"))
        #expect(blocked.fact == nil)
        #expect(blocked.blocked == .factAge)
        // Seven days on, it is one.
        #expect(evaluation(.bestDay, miner, on: day("2026-07-17")).fact != nil)
    }

    // MARK: - Recovery

    /// An overdue clear `hoursLate` past a timed due instant.
    private func overdueClear(
        id: String, localDate: String, minute: Int, hoursLate: Double
    ) -> CompletedTaskStat {
        let day = CivilDay(localDate)!
        let completedAt = Date(
            timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + TimeInterval(minute * 60)
        )
        return makeStat(
            taskId: id, localDate: localDate, localMinute: minute,
            completedAt: completedAt,
            dueAt: completedAt.addingTimeInterval(-hoursLate * 3600),
            hasTime: true
        )
    }

    @Test func threeBarelyLateClearsAreNotADigOut() {
        // Edge case 17: three tasks each 15 minutes late fail the >= 24h
        // qualification.
        let records = (0..<3).map { index in
            overdueClear(id: "t\(index)", localDate: "2026-07-01", minute: 600 + index * 10, hoursLate: 0.25)
        }
        let blocked = evaluation(.recovery, inputs(records: records), on: day("2026-07-20"))
        #expect(blocked.fact == nil)
        #expect(blocked.blocked == .evidence)
    }

    @Test func genuineDigOutMintsARecoveryOnce() {
        let records = [
            overdueClear(id: "deep", localDate: "2026-07-01", minute: 600, hoursLate: 30),
            overdueClear(id: "b", localDate: "2026-07-01", minute: 700, hoursLate: 2),
            overdueClear(id: "c", localDate: "2026-07-02", minute: 600, hoursLate: 3),
        ]
        let qualified = evaluation(.recovery, inputs(records: records), on: day("2026-07-20"))
        #expect(qualified.fact != nil)
        #expect(qualified.fact?.factId.hasPrefix("recovery-") == true)
        #expect(qualified.fact?.sourceDay == day("2026-07-02"))

        // Identity is stable: same episode, same id on re-evaluation.
        let again = evaluation(.recovery, inputs(records: records), on: day("2026-07-21"))
        #expect(again.fact?.factId == qualified.fact?.factId)
    }

    @Test func clearsOutsideTheWindowDoNotCluster() {
        // Two clears now, one three days later: never three inside 48h.
        let records = [
            overdueClear(id: "a", localDate: "2026-07-01", minute: 600, hoursLate: 30),
            overdueClear(id: "b", localDate: "2026-07-01", minute: 700, hoursLate: 2),
            overdueClear(id: "c", localDate: "2026-07-05", minute: 600, hoursLate: 3),
        ]
        let blocked = evaluation(.recovery, inputs(records: records), on: day("2026-07-20"))
        #expect(blocked.fact == nil)
    }

    @Test func recoveryFactAgeFloor() {
        let records = [
            overdueClear(id: "deep", localDate: "2026-07-10", minute: 600, hoursLate: 30),
            overdueClear(id: "b", localDate: "2026-07-10", minute: 700, hoursLate: 2),
            overdueClear(id: "c", localDate: "2026-07-10", minute: 800, hoursLate: 3),
        ]
        let blocked = evaluation(.recovery, inputs(records: records), on: day("2026-07-12"))
        #expect(blocked.blocked == .factAge)
        #expect(evaluation(.recovery, inputs(records: records), on: day("2026-07-17")).fact != nil)
    }

    // MARK: - Streak era

    @Test func streakEraNeedsSevenAndQuietsAfterCelebration() {
        // Edge case 18: streak hit 30 (a milestone) recently; the record
        // belongs to the active run, so it stays quiet for 14 days.
        let fresh = inputs(
            records: [], streak: 30, best: 30,
            achievedOn: "2026-07-05", lastActive: "2026-07-05"
        )
        let blocked = evaluation(.streakEra, fresh, on: day("2026-07-06"))
        #expect(blocked.fact == nil)
        #expect(blocked.blocked == .evidence)

        // 14+ days past the day-30 celebration: eligible (the run is at
        // 30 still only if lastActive is recent; here the run ended).
        let ended = inputs(
            records: [], streak: 2, best: 30,
            achievedOn: "2026-06-01", lastActive: "2026-07-19"
        )
        let qualified = evaluation(.streakEra, ended, on: day("2026-07-20"))
        #expect(qualified.fact?.streakCount == 30)
        #expect(qualified.fact?.eraDated == true)
        #expect(qualified.fact?.factId == "streak-record-30-2026-06-01")
    }

    @Test func belowSevenNeverSurfaces() {
        let miner = inputs(records: [], streak: 6, best: 6, lastActive: "2026-07-19")
        let blocked = evaluation(.streakEra, miner, on: day("2026-07-20"))
        #expect(blocked.fact == nil)
    }

    @Test func legacyRecordGetsCountOnlyIdentityAndNoGuessedDate() {
        // Edge case 19: no achievedOn - era phrasing gated, id uses the
        // legacy sentinel, and the fact still qualifies on count.
        let legacy = inputs(records: [], streak: 1, best: 23, lastActive: "2026-07-19")
        let fact = evaluation(.streakEra, legacy, on: day("2026-07-20")).fact
        #expect(fact?.eraDated == false)
        #expect(fact?.factId == "streak-record-23-legacy")
    }

    @Test func activeRecordRunFactAgeGate() {
        // Record advancing daily (no milestone in the last 14 days:
        // count 25, latest milestone 7 or 30 - 25 has milestone 7 far
        // back, so quiet-days passes) but achieved yesterday: too fresh.
        let active = inputs(
            records: [], streak: 25, best: 25,
            achievedOn: "2026-07-19", lastActive: "2026-07-19"
        )
        let blocked = evaluation(.streakEra, active, on: day("2026-07-20"))
        #expect(blocked.fact == nil)
        #expect(blocked.blocked == .factAge)
    }

    // MARK: - Date echo

    @Test func dateEchoFiresOnMonthAnniversaryOfAQualifyingDay() {
        let records = bigDay("2026-06-08")
        let qualified = evaluation(.dateEcho, inputs(records: records), on: day("2026-07-08"))
        #expect(qualified.fact?.monthsBack == 1)
        #expect(qualified.fact?.count == 5)
        // Cross-type dedup by construction: the echo's id IS the
        // completion-day id best day would mint (edge case 15).
        #expect(qualified.fact?.factId == "completion-day-2026-06-08")

        // Off-date: silence.
        let off = evaluation(.dateEcho, inputs(records: records), on: day("2026-07-09"))
        #expect(off.fact == nil)
    }

    @Test func dateEchoRespectsTheBestDayFloor() {
        let thin = (0..<3).map { index in
            makeStat(taskId: "t\(index)", localDate: "2026-06-08", localMinute: 600 + index)
        }
        let blocked = evaluation(.dateEcho, inputs(records: thin), on: day("2026-07-08"))
        #expect(blocked.fact == nil)
        #expect(blocked.blocked == .evidence)
    }

    @Test func dateEchoUsesClampedMonthMath() {
        // July 31 minus one month clamps to June 30 - platform clamp,
        // same as milestones.
        #expect(CallbackFactMiner.monthsBack(1, from: day("2026-07-31")) == day("2026-06-30"))
        #expect(CallbackFactMiner.monthsBack(1, from: day("2026-03-30")) == day("2026-02-28"))
    }
}
