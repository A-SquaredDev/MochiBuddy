//
//  JournalTimeline.swift
//  MochiBuddy
//
//  The unified story timeline - a merge, not an engine, with pinned
//  calendar semantics: a letter dates by the calendar date of its
//  periodEndExclusive IN THE ZONE STORED ON THAT LETTER; a moment by its
//  date-only occurredOn. Month grouping uses those stored dates, never
//  the device's current timezone - travel cannot move old artifacts
//  between months. Newest first; same-day ties order letters before
//  moments (the richer artifact), then moments by natural id -
//  deterministic on every device.
//
//  Also home to the footer derivations the retired Stats module handed
//  over (week strip + 4-week trend, largely intact). Its on-time and
//  busiest-weekday derivations were deleted with the Feature 6 spec as
//  the recorded reason: a rate is a grade, and an ungated "busiest on
//  Tuesdays" is the confident-wrong-conclusion Feature 4 exists to
//  prevent.
//

import Foundation

enum JournalTimeline {

    /// The charts read four weeks of completions (the Stats constant).
    static let trendDays = 28

    /// The fixed UTC calendar every YYYY-MM-DD string renders through -
    /// stored dates are civil facts, never zone-shifted.
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    // MARK: - Stored-date currency

    /// A letter's timeline date: the calendar date of `periodEndExclusive`
    /// in the letter's own stored zone.
    static func letterDateString(_ letter: Letter) -> String {
        AdoptedOnDate.string(
            from: letter.periodEndExclusive,
            in: TimeZone(identifier: letter.timeZoneId) ?? .current
        )
    }

    /// "Jul 18" from a stored YYYY-MM-DD, rendered verbatim.
    static func dateLabel(_ dateString: String, locale: Locale = .current) -> String {
        guard let day = CivilDay(dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = utcCalendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "MMM d"
        return formatter.string(from: anchor(of: day))
    }

    /// The period's Monday, rendered in the zone the letter was composed
    /// in - a postcard's date never shifts with the reader's travels.
    /// (Inherited from the retired archive screen; the detail header
    /// still renders "Week of July 14" through this.)
    static func weekLabel(for letter: Letter) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: letter.timeZoneId) ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: letter.periodStart)
    }

    /// First non-empty body line - the excerpt every letter surface uses.
    static func excerpt(of letter: Letter) -> String {
        letter.privateRenderedText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
    }

    // MARK: - The merge

    static func monthGroups(
        letters: [Letter],
        moments: [Moment],
        excludingLetterId heroId: String?,
        currentYear: Int,
        locale: Locale = .current
    ) -> [JournalBehavior.MonthGroup] {
        struct Entry {
            let dateString: String
            let isLetter: Bool
            let sortId: String
            let row: JournalBehavior.TimelineRow
        }

        var entries: [Entry] = letters
            .filter { $0.id != heroId }
            .map { letter in
                let date = letterDateString(letter)
                return Entry(
                    dateString: date,
                    isLetter: true,
                    sortId: letter.id,
                    row: .letter(JournalBehavior.LetterRow(
                        letterId: letter.id,
                        dateLabel: dateLabel(date, locale: locale),
                        excerpt: excerpt(of: letter),
                        isUnread: letter.isUnread
                    ))
                )
            }
        entries += moments.map { moment in
            Entry(
                dateString: moment.occurredOn,
                isLetter: false,
                sortId: moment.id,
                row: .moment(JournalBehavior.MomentRow(
                    momentId: moment.id,
                    text: moment.renderedTextSnapshot,
                    dateLabel: dateLabel(moment.occurredOn, locale: locale),
                    icon: icon(for: moment.type),
                    isOrigin: moment.type == .adoption
                ))
            )
        }

        let sorted = entries.sorted { a, b in
            if a.dateString != b.dateString { return a.dateString > b.dateString }
            if a.isLetter != b.isLetter { return a.isLetter }
            return a.sortId < b.sortId
        }

        var groups: [JournalBehavior.MonthGroup] = []
        for entry in sorted {
            let key = String(entry.dateString.prefix(7))
            if groups.last?.id == key {
                let last = groups.removeLast()
                groups.append(JournalBehavior.MonthGroup(
                    id: last.id, title: last.title, rows: last.rows + [entry.row]
                ))
            } else {
                groups.append(JournalBehavior.MonthGroup(
                    id: key,
                    title: monthTitle(key, currentYear: currentYear, locale: locale),
                    rows: [entry.row]
                ))
            }
        }
        return groups
    }

    static func monthTitle(_ monthKey: String, currentYear: Int, locale: Locale = .current) -> String {
        let pieces = monthKey.split(separator: "-")
        guard pieces.count == 2, let year = Int(pieces[0]), let month = Int(pieces[1]),
              let date = utcCalendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return monthKey }
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = utcCalendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = year == currentYear ? "MMMM" : "MMMM yyyy"
        return formatter.string(from: date)
    }

    static func icon(for type: MomentType) -> String {
        // DESIGN NOTE: SF Symbols stand in until commissioned moment art
        // lands (roadmap #6).
        switch type {
        case .adoption: "heart.fill"
        case .anniversary: "sparkles"
        case .streakMilestone: "flame.fill"
        case .vacationReturn: "sun.max.fill"
        case .listReturn: "arrow.uturn.backward"
        }
    }

    // MARK: - Footer derivations (ported from the retired Stats module)

    static func weekCells(
        stats: [CompletedTaskStat],
        weekStart: Date,
        calendar: Calendar
    ) -> [JournalBehavior.DayCell] {
        var countsByDay: [Date: Int] = [:]
        for stat in stats {
            countsByDay[calendar.startOfDay(for: stat.completedAt), default: 0] += 1
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEEE" // narrow weekday - "M", "T", …

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            let count = countsByDay[day] ?? 0
            return JournalBehavior.DayCell(
                id: offset,
                dayLetter: formatter.string(from: day),
                count: count,
                level: min(count, 3)
            )
        }
    }

    static func trendPoints(
        stats: [CompletedTaskStat],
        start: Date,
        calendar: Calendar
    ) -> [JournalBehavior.TrendPoint] {
        var countsByDay: [Date: Int] = [:]
        for stat in stats {
            countsByDay[calendar.startOfDay(for: stat.completedAt), default: 0] += 1
        }
        return (0..<trendDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return JournalBehavior.TrendPoint(id: offset, day: day, count: countsByDay[day] ?? 0)
        }
    }

    /// The trend row renders only once the window spans at least two
    /// distinct civil weeks - a one-week "trend" is noise, not a record.
    static func trendQualifies(stats: [CompletedTaskStat], calendar: Calendar) -> Bool {
        Set(stats.map { CivilDay(of: $0.completedAt, in: calendar).weekKey }).count >= 2
    }

    private static func anchor(of day: CivilDay) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
    }
}
