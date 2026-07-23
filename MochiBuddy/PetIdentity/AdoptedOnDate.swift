//
//  AdoptedOnDate.swift
//  MochiBuddy
//
//  Date-only helpers for `adoptedOn` (YYYY-MM-DD). The value is the literal
//  "day you met" in the timezone where the naming beat completed; it is
//  rendered verbatim with no timezone math, so a zone change can never shift
//  the displayed date.
//

import Foundation

enum AdoptedOnDate {

    /// Fixed-zone calendar used for both stamping arithmetic and display so
    /// parse and format can never disagree about which day a string names.
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// The calendar date of `date` as seen in `timeZone`, as YYYY-MM-DD.
    static func string(from date: Date, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isValid(_ value: String) -> Bool {
        components(of: value) != nil
    }

    /// Long-form display ("July 22, 2026") rendered from the stored value
    /// verbatim - no timezone conversion is ever applied.
    static func displayString(_ value: String, locale: Locale = .current) -> String? {
        guard let parts = components(of: value),
              let date = utcCalendar.date(from: parts)
        else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = utcCalendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private static func components(of value: String) -> DateComponents? {
        let pieces = value.split(separator: "-")
        guard pieces.count == 3,
              pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2])
        else { return nil }
        let parts = DateComponents(year: year, month: month, day: day)
        // Calendar silently rolls invalid dates forward (Feb 30 -> Mar 2);
        // a round-trip mismatch is how we detect them.
        guard let date = utcCalendar.date(from: parts) else { return nil }
        let echo = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard echo.year == year, echo.month == month, echo.day == day else { return nil }
        return parts
    }
}
