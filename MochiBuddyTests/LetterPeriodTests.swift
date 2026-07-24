//
//  LetterPeriodTests.swift
//  MochiBuddyTests
//
//  The letter period contract (Personal Layer, Feature 3): the cutoff IS
//  the period end, the bedtime clamp moves both (they are one instant),
//  identity is a plain date under the authoritative zone.
//
//  Tests pin shipped-default constants and never mutate them (they are
//  process-global; the suite runs in parallel).
//

import Foundation
import Testing
@testable import MochiBuddy

private let chicago = TimeZone(identifier: "America/Chicago")!
private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// An instant built in a specific zone (never the machine's).
private func instant(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
    zone: TimeZone = chicago
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

/// Empty bedtime window: the clamp never applies unless a test asks.
private let noBedtime = BedtimeWindow(startMinutes: 0, endMinutes: 0)

@Suite("Letters · period contract")
struct LetterPeriodTests {

    @Test("a week's period runs Monday 00:00 to Sunday 19:00, id = the Monday")
    func basicShape() {
        // Wed Jul 8 2026, Chicago.
        let period = LetterSchedule.period(
            containing: instant(2026, 7, 8), zone: chicago, bedtime: noBedtime
        )
        #expect(period.start == instant(2026, 7, 6, 0))
        #expect(period.endExclusive == instant(2026, 7, 12, 19))
        #expect(period.id == "letter-2026-07-06")
        #expect(period.timeZoneId == "America/Chicago")
        #expect(period.startDateString == "2026-07-06")
    }

    @Test("a completion at Sunday 20:30 belongs to the NEXT period - by definition")
    func cutoffAttribution() {
        let lateSunday = instant(2026, 7, 12, 20, 30)
        let period = LetterSchedule.period(containing: lateSunday, zone: chicago, bedtime: noBedtime)
        #expect(period.id == "letter-2026-07-13")

        // And that next period's attribution window OWNS the tail.
        let window = LetterSchedule.attributionWindow(of: period, zone: chicago, bedtime: noBedtime)
        #expect(window.contains(lateSunday))
        #expect(window.lowerBound == instant(2026, 7, 12, 19))
    }

    @Test("a bedtime window swallowing the send hour moves the CUTOFF, not just the ping")
    func bedtimeClampMovesCutoff() {
        // Bedtime 18:00 - 07:00: 19:00 falls inside, so the effective
        // send (and cutoff) becomes Sunday 18:00.
        let earlyBedtime = BedtimeWindow(startMinutes: 18 * 60, endMinutes: 7 * 60)
        let period = LetterSchedule.period(
            containing: instant(2026, 7, 8), zone: chicago, bedtime: earlyBedtime
        )
        #expect(period.endExclusive == instant(2026, 7, 12, 18))

        // The standard 22:00 window leaves 19:00 alone.
        let period2 = LetterSchedule.period(
            containing: instant(2026, 7, 8), zone: chicago, bedtime: .standard
        )
        #expect(period2.endExclusive == instant(2026, 7, 12, 19))
    }

    @Test("the previous closed period is last week's, whole week long")
    func previousClosedPeriod() {
        let previous = LetterSchedule.previousClosedPeriod(
            at: instant(2026, 7, 8), zone: chicago, bedtime: noBedtime
        )
        #expect(previous.id == "letter-2026-06-29")
        #expect(previous.endExclusive <= instant(2026, 7, 8))
    }

    @Test("early Monday, before anything: the previous period is already closed")
    func mondayMorningClosesLastWeek() {
        let previous = LetterSchedule.previousClosedPeriod(
            at: instant(2026, 7, 13, 8), zone: chicago, bedtime: noBedtime
        )
        #expect(previous.id == "letter-2026-07-06")
    }

    @Test("a period spanning New Year keeps a plain date id - no ISO week-year trap")
    func newYearIdentity() {
        // Jan 1 2026 is a Thursday; its week's Monday is Dec 29 2025.
        let period = LetterSchedule.period(
            containing: instant(2026, 1, 1), zone: chicago, bedtime: noBedtime
        )
        #expect(period.id == "letter-2025-12-29")
    }

    @Test("period identity derives from the GIVEN zone - the authoritative one")
    func zoneParameterIsAuthoritative() {
        // Sunday 23:00 UTC = Sunday evening Chicago but Monday morning
        // Tokyo: the zone parameter decides which period this instant
        // belongs to, which is why the synced profile zone must be used.
        let utcInstant = instant(2026, 7, 13, 8, zone: tokyo) // Mon 08:00 Tokyo
        let inTokyo = LetterSchedule.period(containing: utcInstant, zone: tokyo, bedtime: noBedtime)
        let inChicago = LetterSchedule.period(containing: utcInstant, zone: chicago, bedtime: noBedtime)
        #expect(inTokyo.id == "letter-2026-07-13")
        #expect(inChicago.id == "letter-2026-07-06", "still Sunday evening in Chicago")
    }

    @Test("the first eligible period is the first FULL week after adoption")
    func firstEligiblePeriod() {
        // Adopted Wed Jul 8: the Jul 6 week is partial; eligibility
        // starts Monday Jul 13.
        let first = LetterSchedule.firstEligiblePeriodStart(
            adoptedOn: "2026-07-08", zone: chicago, bedtime: noBedtime
        )
        #expect(first == instant(2026, 7, 13, 0))

        // Adopted ON a Monday: that whole week is still the adoption
        // week; the first full period starts the following Monday.
        let mondayAdoption = LetterSchedule.firstEligiblePeriodStart(
            adoptedOn: "2026-07-06", zone: chicago, bedtime: noBedtime
        )
        #expect(mondayAdoption == instant(2026, 7, 13, 0))

        #expect(LetterSchedule.firstEligiblePeriodStart(
            adoptedOn: "garbage", zone: chicago, bedtime: noBedtime
        ) == nil)
    }
}
