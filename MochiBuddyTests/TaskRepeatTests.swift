//
//  TaskRepeatTests.swift
//  MochiBuddyTests
//
//  Repeat stepping — completing an occurrence spawns the next one strictly
//  after now, skipping any occurrences that already slipped past.
//
//  Anchor: Dates.now is Wed 8 Jul 2026, 10:00 (Jul 10 = Friday).
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("TaskRepeat · nextOccurrence")
struct TaskRepeatTests {

    private let calendar = Dates.calendar

    private func at(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
    }

    // MARK: Daily

    @Test("daily from a future occurrence steps one day")
    func dailyFuture() {
        // Due today 9pm, completed early at 10am → next is tomorrow 9pm.
        let next = TaskRepeat.daily.nextOccurrence(after: at(8, 21), now: Dates.now, calendar: calendar)
        #expect(next == at(9, 21))
    }

    @Test("daily overdue skips the occurrences that already passed")
    func dailySkipsMissed() {
        // Due 4 days ago at 9am, completed today at 10am → today 9am has
        // also passed, so the next occurrence is TOMORROW 9am.
        let next = TaskRepeat.daily.nextOccurrence(after: at(4), now: Dates.now, calendar: calendar)
        #expect(next == at(9))
    }

    @Test("the next occurrence is always strictly after now")
    func strictlyAfterNow() {
        for rule in TaskRepeat.allCases {
            let next = rule.nextOccurrence(after: at(1), now: Dates.now, calendar: calendar)
            #expect(next > Dates.now, "\(rule.rawValue) produced \(next), not after now")
        }
    }

    // MARK: Weekdays

    @Test("weekdays skips the weekend: Friday → Monday")
    func weekdaysSkipWeekend() {
        // Friday Jul 10 → Monday Jul 13.
        let friday = at(10)
        let next = TaskRepeat.weekdays.nextOccurrence(after: friday, now: friday, calendar: calendar)
        #expect(next == at(13))
        #expect(!calendar.isDateInWeekend(next))
    }

    @Test("weekdays midweek is just the next day")
    func weekdaysMidweek() {
        // Wed Jul 8 (due 9am, completed 10am) → Thu Jul 9.
        let next = TaskRepeat.weekdays.nextOccurrence(after: at(8), now: Dates.now, calendar: calendar)
        #expect(next == at(9))
    }

    @Test("weekdays never lands on a weekend even when skipping many missed days")
    func weekdaysNeverWeekend() {
        // Due 3 weeks ago; whatever it lands on must be a weekday after now.
        let old = calendar.date(byAdding: .day, value: -21, to: at(8))!
        let next = TaskRepeat.weekdays.nextOccurrence(after: old, now: Dates.now, calendar: calendar)
        #expect(next > Dates.now)
        #expect(!calendar.isDateInWeekend(next))
    }

    // MARK: Weekly / Monthly

    @Test("weekly steps exactly seven days")
    func weekly() {
        let next = TaskRepeat.weekly.nextOccurrence(after: at(8), now: Dates.now, calendar: calendar)
        #expect(next == at(15))
    }

    @Test("weekly overdue by two weeks skips to the first future week")
    func weeklySkips() {
        let old = calendar.date(byAdding: .day, value: -14, to: at(8))!
        let next = TaskRepeat.weekly.nextOccurrence(after: old, now: Dates.now, calendar: calendar)
        #expect(next == at(15))
    }

    @Test("monthly steps one calendar month")
    func monthly() {
        let next = TaskRepeat.monthly.nextOccurrence(after: at(8), now: Dates.now, calendar: calendar)
        let expected = calendar.date(byAdding: .month, value: 1, to: at(8))!
        #expect(next == expected)
    }

    @Test("monthly from Jan 31 clamps to the shorter month instead of crashing")
    func monthlyEndOfMonth() {
        let jan31 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
        let next = TaskRepeat.monthly.nextOccurrence(after: jan31, now: jan31, calendar: calendar)
        let expected = calendar.date(byAdding: .month, value: 1, to: jan31)!
        #expect(next == expected)
        // 2026 is not a leap year — February clamp lands on the 28th.
        #expect(calendar.component(.day, from: next) == 28)
    }

    @Test("preserves the time of day across steps")
    func preservesTime() {
        let due = at(8, 17) // 5pm
        let next = TaskRepeat.daily.nextOccurrence(after: due, now: Dates.now, calendar: calendar)
        #expect(calendar.component(.hour, from: next) == 17)
    }
}
