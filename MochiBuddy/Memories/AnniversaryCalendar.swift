//
//  AnniversaryCalendar.swift
//  MochiBuddy
//
//  Relationship milestones (Personal Layer, Feature 2): 1 week, 1 month,
//  then yearly, all pure date-only math from the write-once adoptedOn.
//  No stored schedule, no state: today's local date either equals a
//  milestone date or it does not, and after the day nobody composes it.
//
//  Calendar-clamped exactly like the platform clamps: adoption on Jan 31
//  puts the month mark on Feb 28/29; adoption on Feb 29 puts the yearly
//  mark on Feb 28 in non-leap years. Deliberately NOT remote-tunable -
//  these are calendar facts, not levers.
//

import Foundation

enum AnniversaryTier: Equatable, Hashable {
    case week
    case month
    case year(Int)

    /// Coarse label for telemetry (never a date).
    var telemetryLabel: String {
        switch self {
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }

    /// Month-and-larger marks earn a past-tense acknowledgment after a
    /// vacation; the 1-week mark is too small to backdate.
    var deferrable: Bool {
        self != .week
    }
}

struct AnniversaryMilestone: Equatable {
    let tier: AnniversaryTier
    /// The milestone's own civil date (YYYY-MM-DD).
    let day: CivilDay

    /// Stable identity for the banner's once-per-day ledger entry.
    var id: String {
        let tierKey = switch tier {
        case .week: "week"
        case .month: "month"
        case .year(let n): "year\(n)"
        }
        return "anniversary-\(tierKey)-\(day.dateString)"
    }
}

enum AnniversaryCalendar {

    /// The same fixed UTC Gregorian calendar CivilDay is backed by, so
    /// component math and day arithmetic can never disagree.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private static func anchor(of day: CivilDay) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
    }

    /// Adds whole months/years with the platform's own clamping.
    private static func adding(months: Int = 0, years: Int = 0, to day: CivilDay) -> CivilDay? {
        var parts = DateComponents()
        parts.month = months
        parts.year = years
        guard let shifted = utcCalendar.date(byAdding: parts, to: anchor(of: day)) else { return nil }
        return CivilDay(of: shifted, in: utcCalendar)
    }

    /// The milestone landing on a civil date, if any. Nil for malformed
    /// or missing adoption dates - a missing foundation means silence,
    /// never a guess.
    static func milestone(adoptedOn: String?, on day: CivilDay) -> AnniversaryMilestone? {
        guard let adoptedOn, let adopted = CivilDay(adoptedOn), day > adopted else { return nil }

        if day.dayNumber == adopted.dayNumber + 7 {
            return AnniversaryMilestone(tier: .week, day: day)
        }
        if adding(months: 1, to: adopted) == day {
            return AnniversaryMilestone(tier: .month, day: day)
        }
        let adoptedYear = utcCalendar.component(.year, from: anchor(of: adopted))
        let dayYear = utcCalendar.component(.year, from: anchor(of: day))
        let n = dayYear - adoptedYear
        if n >= 1, adding(years: n, to: adopted) == day {
            return AnniversaryMilestone(tier: .year(n), day: day)
        }
        return nil
    }

    /// All milestones whose date falls inside a closed civil-day range,
    /// ascending. Ranges here are short (a trip, a letter week) - a day
    /// walk is the simplest correct scan.
    static func milestones(adoptedOn: String?, from start: CivilDay, through end: CivilDay) -> [AnniversaryMilestone] {
        guard start <= end else { return [] }
        var found: [AnniversaryMilestone] = []
        var day = start
        while day <= end {
            if let milestone = milestone(adoptedOn: adoptedOn, on: day) {
                found.append(milestone)
            }
            day = day.advanced(by: 1)
        }
        return found
    }

    /// The month-and-larger milestone that passed during a vacation whose
    /// TRUE end (stamped at re-entry) falls inside this rundown's wake
    /// window - which makes this rundown the first one after re-entry.
    /// Fully derived from the synced interval log: no stored deferral
    /// state, so a device that never saw the trip computes the same
    /// answer. Returns the most recent qualifying mark.
    ///
    /// "Truly silent" held during the trip; the mark's own date already
    /// passed, so the acknowledgment is past-tense and honest about it.
    /// A 1-week mark is never deferred, and a rundown-toggle-off user
    /// simply has no rundown to carry it - skipped, deliberately.
    static func deferredAcknowledgment(
        adoptedOn: String?,
        intervals: [ObservationInterval],
        wake: Date,
        previousWake: Date,
        calendar: Calendar
    ) -> AnniversaryMilestone? {
        guard adoptedOn != nil else { return nil }
        let ended = intervals.filter { interval in
            guard interval.kind == .vacation, let end = interval.end else { return false }
            return end > previousWake && end <= wake
        }
        guard let trip = ended.max(by: { ($0.end ?? .distantPast) < ($1.end ?? .distantPast) }),
              let tripEnd = trip.end
        else { return nil }

        let startDay = CivilDay(of: trip.start, in: calendar)
        // The end day itself is "today" territory: a mark landing on the
        // re-entry day surfaces normally, not as a memory.
        let lastCoveredDay = CivilDay(of: tripEnd, in: calendar).advanced(by: -1)
        return milestones(adoptedOn: adoptedOn, from: startDay, through: lastCoveredDay)
            .last { $0.tier.deferrable }
    }

    /// The next milestone date on or after a day - dev inspector only.
    static func nextMilestone(adoptedOn: String?, onOrAfter day: CivilDay) -> AnniversaryMilestone? {
        guard adoptedOn != nil else { return nil }
        var probe = day
        // A yearly mark is never more than ~13 months out.
        for _ in 0..<400 {
            if let milestone = milestone(adoptedOn: adoptedOn, on: probe) { return milestone }
            probe = probe.advanced(by: 1)
        }
        return nil
    }
}
