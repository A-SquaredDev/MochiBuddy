//
//  RecurrenceRollerTests.swift
//  MochiBuddyTests
//
//  The one-live-occurrence invariant: a neglected recurring task rolls
//  forward when its next occurrence comes due, so lateness never exceeds
//  one period, and the misses are logged silently.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("RecurrenceRoller")
@MainActor
struct RecurrenceRollerTests {

    private func makeRoller() -> (RecurrenceRoller, StubTaskRepository) {
        let repo = StubTaskRepository()
        return (RecurrenceRoller(taskRepository: repo), repo)
    }

    // Dates.now is Wed 8 Jul 2026, 10:00 local.

    @Test("a timed daily habit two days behind re-stamps to today's occurrence")
    func timedDailyRolls() async {
        let (roller, repo) = makeRoller()
        // Due Mon 9:00; Tue 9:00 and Wed 9:00 have both come due by Wed 10:00.
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 6, hour: 9)
        )!
        let task = makeTask(id: "habit", dueAt: due, hasTime: true, repeatRule: .daily)

        let rolled = await roller.rollForward([task], userId: "user1", now: Dates.now)

        let expected = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)
        )!
        #expect(rolled.first?.dueAt == expected)
        #expect(repo.rollForwardCalls.count == 1)
        #expect(repo.rollForwardCalls.first?.newDueAt == expected)
        #expect(repo.rollForwardCalls.first?.missed == 2)
    }

    @Test("under one period late stays put - lateness is real, bounded stress")
    func withinOnePeriodDoesNotRoll() async {
        let (roller, repo) = makeRoller()
        // Due Wed 9:00, one hour late; tomorrow's occurrence isn't due yet.
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)
        )!
        let task = makeTask(id: "habit", dueAt: due, hasTime: true, repeatRule: .daily)

        let rolled = await roller.rollForward([task], userId: "user1", now: Dates.now)

        #expect(rolled.first?.dueAt == due)
        #expect(repo.rollForwardCalls.isEmpty)
    }

    @Test("date-only daily due yesterday holds - today's occurrence isn't overdue until end of day")
    func dateOnlyYesterdayHolds() async {
        let (roller, repo) = makeRoller()
        let task = makeTask(id: "habit", dueAt: Dates.days(-1), repeatRule: .daily)

        let rolled = await roller.rollForward([task], userId: "user1", now: Dates.now)

        #expect(rolled.first?.dueAt == Dates.days(-1))
        #expect(repo.rollForwardCalls.isEmpty)
    }

    @Test("date-only daily four days behind re-stamps to yesterday, three misses logged")
    func dateOnlyDeepBacklogRolls() async {
        let (roller, repo) = makeRoller()
        let task = makeTask(id: "habit", dueAt: Dates.days(-4), repeatRule: .daily)

        let rolled = await roller.rollForward([task], userId: "user1", now: Dates.now)

        #expect(rolled.first?.dueAt == Dates.days(-1))
        #expect(repo.rollForwardCalls.first?.missed == 3)
    }

    @Test("a weekly task five days late keeps aging - it hasn't reached the next occurrence")
    func weeklyKeepsAgingPastTheCap() async {
        let (roller, repo) = makeRoller()
        // Due last Fri 9:00; next occurrence is this Fri - not due yet, so
        // lateness runs past the 48h H_MAX cap and hits full sting.
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 3, hour: 9)
        )!
        let task = makeTask(id: "review", dueAt: due, hasTime: true, repeatRule: .weekly)

        let rolled = await roller.rollForward([task], userId: "user1", now: Dates.now)

        #expect(rolled.first?.dueAt == due)
        #expect(repo.rollForwardCalls.isEmpty)
    }

    @Test("frozen (vacation or lapsed) never advances recurrence")
    func frozenNeverRolls() async {
        let (roller, repo) = makeRoller()
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 1, hour: 9)
        )!
        let task = makeTask(id: "habit", dueAt: due, hasTime: true, repeatRule: .daily)

        let rolled = await roller.rollForward([task], frozen: true, userId: "user1", now: Dates.now)

        #expect(rolled.first?.dueAt == due)
        #expect(repo.rollForwardCalls.isEmpty)
    }

    @Test("non-recurring and undated tasks pass through untouched")
    func nonRecurringPassesThrough() async {
        let (roller, repo) = makeRoller()
        let oneOff = makeTask(id: "one-off", dueAt: Dates.days(-5))
        let undatedHabit = makeTask(id: "someday", repeatRule: .daily)

        let rolled = await roller.rollForward([oneOff, undatedHabit], userId: "user1", now: Dates.now)

        #expect(rolled == [oneOff, undatedHabit])
        #expect(repo.rollForwardCalls.isEmpty)
    }
}
