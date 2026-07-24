//
//  LetterPeriod.swift
//  MochiBuddy
//
//  The letter period (Personal Layer, Feature 3): begins Monday 00:00 and
//  ends at the EFFECTIVE send time on the send day - letter_send_hour, or
//  the bedtime clamp if earlier. The period end IS the cutoff: completions
//  after it belong to the next period, which is what lets the Sunday-
//  evening ritual and "compose only over a closed period" both be true.
//
//  All math takes the timezone explicitly - the authoritative zone is the
//  synced profile timezone, never whichever zone a device happens to be
//  in (a phone and iPad near a zone boundary must identify the same
//  period, or one-letter-ever fails). Identity is the period's Monday as
//  a plain date: "letter-2026-07-20". Deliberately NOT an ISO week id -
//  calendar year and week-based year diverge around New Year.
//

import Foundation

struct LetterPeriod: Equatable {
    /// Monday 00:00 in the authoritative zone.
    let start: Date
    /// The effective send instant - the cutoff. Stored on the letter so
    /// there is never later ambiguity about what it covered.
    let endExclusive: Date
    /// IANA id of the zone the boundaries were computed in.
    let timeZoneId: String
    /// YYYY-MM-DD of the starting Monday, in that zone.
    let startDateString: String

    var id: String { "letter-\(startDateString)" }
}

enum LetterSchedule {

    static func calendar(for zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The period whose week contains `instant`, by calendar position -
    /// use `period(containing:)` for attribution (the cutoff shifts it).
    static func period(inWeekOf instant: Date, zone: TimeZone, bedtime: BedtimeWindow) -> LetterPeriod {
        let calendar = calendar(for: zone)
        var day = calendar.startOfDay(for: instant)
        // Walk back to Monday (calendar weekday 2), at most six steps.
        var hops = 0
        while calendar.component(.weekday, from: day) != 2, hops < 6 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            hops += 1
        }
        return period(startingMonday: day, calendar: calendar, zone: zone, bedtime: bedtime)
    }

    /// The period a completion at `instant` BELONGS to: past this week's
    /// cutoff means the next period (Sunday 20:30 → next letter, by
    /// definition, not by accident).
    static func period(containing instant: Date, zone: TimeZone, bedtime: BedtimeWindow) -> LetterPeriod {
        let calendar = calendar(for: zone)
        let thisWeek = period(inWeekOf: instant, zone: zone, bedtime: bedtime)
        guard instant >= thisWeek.endExclusive else { return thisWeek }
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: thisWeek.start) ?? thisWeek.start
        return period(startingMonday: nextMonday, calendar: calendar, zone: zone, bedtime: bedtime)
    }

    /// The most recent period fully closed at `now` - the composition
    /// candidate.
    static func previousClosedPeriod(at now: Date, zone: TimeZone, bedtime: BedtimeWindow) -> LetterPeriod {
        let calendar = calendar(for: zone)
        let current = period(containing: now, zone: zone, bedtime: bedtime)
        let previousMonday = calendar.date(byAdding: .day, value: -7, to: current.start) ?? current.start
        return period(startingMonday: previousMonday, calendar: calendar, zone: zone, bedtime: bedtime)
    }

    /// The completion-attribution window: the previous period's cutoff up
    /// to this period's cutoff. A period "owns" the Sunday-evening tail of
    /// the week before it (the hours after the previous cutoff).
    static func attributionWindow(
        of period: LetterPeriod, zone: TimeZone, bedtime: BedtimeWindow
    ) -> Range<Date> {
        let calendar = calendar(for: zone)
        let previousMonday = calendar.date(byAdding: .day, value: -7, to: period.start) ?? period.start
        let previous = self.period(startingMonday: previousMonday, calendar: calendar, zone: zone, bedtime: bedtime)
        return previous.endExclusive..<period.endExclusive
    }

    /// The first period eligible for a letter: the first FULL period after
    /// adoption. The adoption week's own (partial) period never composes;
    /// in-app day-1 delight carries the early experience.
    static func firstEligiblePeriodStart(
        adoptedOn: String, zone: TimeZone, bedtime: BedtimeWindow
    ) -> Date? {
        // adoptedOn is date-only (YYYY-MM-DD, validated at persistence);
        // anchor mid-day in the zone so the week walk-back can't straddle.
        guard CivilDay(adoptedOn) != nil else { return nil }
        let calendar = calendar(for: zone)
        guard let anchor = calendar.date(from: DateComponents(
            year: Int(adoptedOn.prefix(4)),
            month: Int(adoptedOn.dropFirst(5).prefix(2)),
            day: Int(adoptedOn.suffix(2)),
            hour: 12
        )) else { return nil }
        let adoptionWeek = period(inWeekOf: anchor, zone: zone, bedtime: bedtime)
        return calendar.date(byAdding: .day, value: 7, to: adoptionWeek.start)
    }

    // MARK: - Internals

    private static func period(
        startingMonday start: Date, calendar: Calendar, zone: TimeZone, bedtime: BedtimeWindow
    ) -> LetterPeriod {
        // The send day: first day in the week with the configured weekday
        // (default Sunday = the week's last day).
        var sendDay = start
        for offset in 0...6 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            sendDay = day
            if calendar.component(.weekday, from: day) == LetterConstants.sendWeekday {
                break
            }
        }
        let sendInstant = calendar.date(
            byAdding: .minute, value: LetterConstants.sendHour * 60,
            to: calendar.startOfDay(for: sendDay)
        ) ?? sendDay

        // Bedtime clamp: when the send hour falls inside the quiet window,
        // the send (and therefore the CUTOFF - one instant) moves to the
        // window's start that day. Only ever earlier, never later.
        var endExclusive = sendInstant
        if bedtime.contains(sendInstant, calendar: calendar) {
            let clamped = calendar.date(
                byAdding: .minute, value: bedtime.startMinutes,
                to: calendar.startOfDay(for: sendDay)
            ) ?? sendInstant
            if clamped < sendInstant, clamped > start {
                endExclusive = clamped
            }
        }

        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        return LetterPeriod(
            start: start,
            endExclusive: endExclusive,
            timeZoneId: zone.identifier,
            startDateString: String(
                format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
            )
        )
    }
}
