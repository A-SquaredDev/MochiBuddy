//
//  AnniversaryCalendarTests.swift
//  MochiBuddyTests
//
//  Feature 2 date math: milestone recurrence, the platform clamps,
//  date-only comparison, and the stateless vacation deferral.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct AnniversaryCalendarTests {

    private func day(_ string: String) -> CivilDay { CivilDay(string)! }

    // MARK: - Milestone set

    @Test func weekMarkIsSevenDaysAfterAdoption() {
        let milestone = AnniversaryCalendar.milestone(adoptedOn: "2026-07-01", on: day("2026-07-08"))
        #expect(milestone == AnniversaryMilestone(tier: .week, day: day("2026-07-08")))
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-01", on: day("2026-07-07")) == nil)
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-01", on: day("2026-07-09")) == nil)
    }

    @Test func monthMarkOnPlainDates() {
        let milestone = AnniversaryCalendar.milestone(adoptedOn: "2026-07-15", on: day("2026-08-15"))
        #expect(milestone?.tier == .month)
        // The day after is not a mark; after the day nobody composes it.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-15", on: day("2026-08-16")) == nil)
    }

    @Test func yearlyRecurrence() {
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-15", on: day("2027-07-15"))?.tier == .year(1))
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-15", on: day("2029-07-15"))?.tier == .year(3))
        // Only whole years; month marks past the first do not exist.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-15", on: day("2026-09-15")) == nil)
    }

    // MARK: - Clamps (edge case 7)

    @Test func jan31AdoptionClampsMonthMarkToFebEnd() {
        // 2026 is not a leap year: Jan 31 + 1 month clamps to Feb 28.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-01-31", on: day("2026-02-28"))?.tier == .month)
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-01-31", on: day("2026-03-01")) == nil)
        // 2028 is a leap year: Jan 31 + 1 month clamps to Feb 29.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2028-01-31", on: day("2028-02-29"))?.tier == .month)
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2028-01-31", on: day("2028-02-28")) == nil)
    }

    @Test func feb29AdoptionClampsYearlyMarkInNonLeapYears() {
        // 2028-02-29 exists; 2029 clamps the yearly mark to Feb 28.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2028-02-29", on: day("2029-02-28"))?.tier == .year(1))
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2028-02-29", on: day("2029-03-01")) == nil)
        // The next leap year lands back on the true date.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2028-02-29", on: day("2032-02-29"))?.tier == .year(4))
    }

    // MARK: - Guards

    @Test func missingOrMalformedAdoptionMeansSilence() {
        #expect(AnniversaryCalendar.milestone(adoptedOn: nil, on: day("2026-07-08")) == nil)
        #expect(AnniversaryCalendar.milestone(adoptedOn: "garbage", on: day("2026-07-08")) == nil)
        // The adoption day itself is day zero, not a milestone.
        #expect(AnniversaryCalendar.milestone(adoptedOn: "2026-07-08", on: day("2026-07-08")) == nil)
    }

    @Test func rangeScanFindsMilestonesAscending() {
        let found = AnniversaryCalendar.milestones(
            adoptedOn: "2026-07-01", from: day("2026-07-01"), through: day("2026-08-31")
        )
        #expect(found.map(\.tier) == [.week, .month])
        #expect(found.map(\.day.dateString) == ["2026-07-08", "2026-08-01"])
    }

    @Test func milestoneIdsAreStable() {
        let milestone = AnniversaryCalendar.milestone(adoptedOn: "2026-07-15", on: day("2027-07-15"))
        #expect(milestone?.id == "anniversary-year1-2027-07-15")
    }

    // MARK: - Vacation deferral (edge cases 3, 5)

    private let calendar = Calendar.current

    private func instant(_ dateString: String, hour: Int = 12) -> Date {
        let day = CivilDay(dateString)!
        return Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + TimeInterval(hour) * 3600)
    }

    @Test func monthMarkPassedOnVacationDefersToFirstReentryRundown() {
        // Adoption 2026-06-01, month mark 2026-07-01. Vacation covered
        // 06-25 through 07-03; the first wake after re-entry is 07-04.
        let intervals = [ObservationInterval(
            kind: .vacation, start: instant("2026-06-25"), end: instant("2026-07-03", hour: 15)
        )]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let deferred = AnniversaryCalendar.deferredAcknowledgment(
            adoptedOn: "2026-06-01",
            intervals: intervals,
            wake: instant("2026-07-04", hour: 7),
            previousWake: instant("2026-07-03", hour: 7),
            calendar: utc
        )
        #expect(deferred?.tier == .month)

        // The NEXT morning's rundown is no longer first post-re-entry:
        // nothing, deterministically, with zero stored state.
        let later = AnniversaryCalendar.deferredAcknowledgment(
            adoptedOn: "2026-06-01",
            intervals: intervals,
            wake: instant("2026-07-05", hour: 7),
            previousWake: instant("2026-07-04", hour: 7),
            calendar: utc
        )
        #expect(later == nil)
    }

    @Test func weekMarkPassedOnVacationIsSkipped() {
        // Adoption 2026-06-20, week mark 2026-06-27, inside the trip.
        let intervals = [ObservationInterval(
            kind: .vacation, start: instant("2026-06-25"), end: instant("2026-07-03", hour: 15)
        )]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let deferred = AnniversaryCalendar.deferredAcknowledgment(
            adoptedOn: "2026-06-20",
            intervals: intervals,
            wake: instant("2026-07-04", hour: 7),
            previousWake: instant("2026-07-03", hour: 7),
            calendar: utc
        )
        #expect(deferred == nil)
    }

    @Test func openOrUnrelatedIntervalsDeferNothing() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // Still-open vacation: no true end, nothing to acknowledge yet.
        let open = [ObservationInterval(kind: .vacation, start: instant("2026-06-25"), end: nil)]
        #expect(AnniversaryCalendar.deferredAcknowledgment(
            adoptedOn: "2026-06-01", intervals: open,
            wake: instant("2026-07-04", hour: 7), previousWake: instant("2026-07-03", hour: 7),
            calendar: utc
        ) == nil)
        // A lapse interval never earns an acknowledgment (edge case 6:
        // lapse anniversaries are skipped entirely, never backdated).
        let lapse = [ObservationInterval(
            kind: .lapse, start: instant("2026-06-25"), end: instant("2026-07-03", hour: 15)
        )]
        #expect(AnniversaryCalendar.deferredAcknowledgment(
            adoptedOn: "2026-06-01", intervals: lapse,
            wake: instant("2026-07-04", hour: 7), previousWake: instant("2026-07-03", hour: 7),
            calendar: utc
        ) == nil)
    }

    @Test func markLandingOnReentryDayIsNotDeferred() {
        // Vacation ends the morning of the mark itself: it surfaces
        // normally as "today", never past-tense.
        let intervals = [ObservationInterval(
            kind: .vacation, start: instant("2026-06-25"), end: instant("2026-07-01", hour: 9)
        )]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let deferred = AnniversaryCalendar.deferredAcknowledgment(
            adoptedOn: "2026-06-01",
            intervals: intervals,
            wake: instant("2026-07-01", hour: 10),
            previousWake: instant("2026-06-30", hour: 10),
            calendar: utc
        )
        #expect(deferred == nil)
    }
}
