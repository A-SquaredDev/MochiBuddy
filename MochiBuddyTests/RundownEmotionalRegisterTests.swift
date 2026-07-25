//
//  RundownEmotionalRegisterTests.swift
//  MochiBuddyTests
//
//  Feature 2's mood gate: computed from the predicted BASELINE at the
//  rundown's fire time (never the buffer-lifted displayed mood), with
//  the chronic-taper stretch closing the register. The comfort buffer
//  changing nothing is the load-bearing assertion - a pet must never
//  unlock trophy copy for an anxious user (edge cases 10, 11, 12).
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct RundownEmotionalRegisterTests {

    private let fireAt = Dates.hours(8)

    /// Overdue-by-two-days high-priority tasks push the baseline down
    /// deterministically (0 = content anchor territory).
    private func snapshot(overdueHigh: Int, boosts: [BufferBoost] = []) -> MoodSnapshot {
        let tasks = (0..<overdueHigh).map { index in
            makeTask(
                id: "over\(index)", dueAt: Dates.hours(-48), hasTime: true, priority: .high
            )
        }
        return MoodSnapshot(tasks: tasks, boosts: boosts, capturedAt: Dates.now)
    }

    @Test func contentAndAboveOpensEveryType() {
        let register = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 0),
            taper: TaperState(), calendar: Dates.calendar
        )
        #expect(register == .open)
        #expect(CallbackType.allCases.allSatisfy { register.admits($0) })
    }

    @Test func anxiousAdmitsRecoveryOnly() {
        let register = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 2),
            taper: TaperState(), calendar: Dates.calendar
        )
        #expect(register == .recoveryOnly)
        #expect(register.admits(.recovery))
        #expect(!register.admits(.bestDay))
        #expect(!register.admits(.streakEra))
        #expect(!register.admits(.dateEcho))
    }

    @Test func floorClosesEverything() {
        let register = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 6),
            taper: TaperState(), calendar: Dates.calendar
        )
        #expect(register == .closed)
        #expect(CallbackType.allCases.allSatisfy { !register.admits($0) })
    }

    @Test func bufferLiftChangesNothing() {
        // A fresh full-cap pet: displayed mood jumps 30 points, the
        // register does not move (baseline is the input, and baseline
        // never includes boosts).
        let boost = [BufferBoost(lift: 30, startedAt: Dates.now, duration: 24 * 3600)]
        let without = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 2),
            taper: TaperState(), calendar: Dates.calendar
        )
        let with = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 2, boosts: boost),
            taper: TaperState(), calendar: Dates.calendar
        )
        #expect(without == with)
        #expect(with == .recoveryOnly)
        // Sanity: the displayed value really would band differently.
        let displayed = MoodForecast.displayed(
            at: fireAt, snapshot: snapshot(overdueHigh: 2, boosts: boost), calendar: Dates.calendar
        )
        let baseline = MoodForecast.baseline(
            at: fireAt, snapshot: snapshot(overdueHigh: 2, boosts: boost), calendar: Dates.calendar
        )
        #expect(MoodBand(value: displayed) != MoodBand(value: baseline))
    }

    @Test func chronicTaperStretchClosesAnUneasyMorning() {
        // Day 4 of a floor stretch, morning blip up to uneasy: still a
        // chronic-taper day - the pure-presence copy owns the register.
        let taper = TaperState(
            firstFloorDay: Dates.hours(-24 * 4),
            lastFloorDay: Dates.hours(-24),
            goodSince: nil
        )
        let register = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 1),
            taper: taper, calendar: Dates.calendar
        )
        #expect(register == .closed)

        // A cleared taper (recovery held, state wiped) frees the same
        // uneasy morning back to recovery-only.
        let cleared = RundownEmotionalRegister.evaluate(
            fireAt: fireAt, snapshot: snapshot(overdueHigh: 1),
            taper: TaperState(), calendar: Dates.calendar
        )
        #expect(cleared == .recoveryOnly)
    }
}
