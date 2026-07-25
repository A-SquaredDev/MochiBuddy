//
//  PeriodSummaryBuilder.swift
//  MochiBuddy
//
//  Pure aggregation from server-backed state to the composer's
//  PeriodSummary (Personal Layer, Feature 3). Everything here is a static
//  function of its inputs - the composition service does the fetching,
//  this file does the thinking, tests pin the thinking.
//

import Foundation

enum PeriodSummaryBuilder {

    static let weekdayNames = [
        "", "Sunday", "Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday",
    ]

    // MARK: - Classification facts

    /// Tasks that came due inside the window - completed or still open.
    static func tasksDueCount(
        stats: [CompletedTaskStat], incomplete: [TaskItem], window: Range<Date>
    ) -> Int {
        let completedDue = stats.filter {
            guard let dueAt = $0.dueAt else { return false }
            return window.contains(dueAt)
        }.count
        let openDue = incomplete.filter {
            guard let dueAt = $0.dueAt else { return false }
            return window.contains(dueAt)
        }.count
        return completedDue + openDue
    }

    /// Days in the window on which at least one task sat overdue: the
    /// span [overdue boundary, completion-or-window-end) overlapping the
    /// day. Derived from completion records + still-open tasks; deleted
    /// tasks are honestly out (composition happens once, behind the
    /// barrier - purity matters here, cross-device agreement does not).
    static func overdueDayCount(
        stats: [CompletedTaskStat],
        incomplete: [TaskItem],
        window: Range<Date>,
        zone: TimeZone
    ) -> Int {
        var spans: [Range<Date>] = []
        let calendar = LetterSchedule.calendar(for: zone)
        for stat in stats {
            guard let dueAt = stat.dueAt else { continue }
            let boundary = overdueBoundary(dueAt: dueAt, hasTime: stat.hasTime, calendar: calendar)
            if boundary < stat.completedAt {
                spans.append(boundary..<stat.completedAt)
            }
        }
        for task in incomplete {
            guard let dueAt = task.dueAt else { continue }
            let boundary = overdueBoundary(dueAt: dueAt, hasTime: task.hasTime, calendar: calendar)
            if boundary < window.upperBound {
                spans.append(boundary..<window.upperBound)
            }
        }

        var overdueDays = 0
        var dayStart = calendar.startOfDay(for: window.lowerBound)
        while dayStart < window.upperBound {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? window.upperBound
            let day = max(dayStart, window.lowerBound)..<min(dayEnd, window.upperBound)
            if spans.contains(where: { $0.overlaps(day) }) {
                overdueDays += 1
            }
            dayStart = dayEnd
        }
        return overdueDays
    }

    private static func overdueBoundary(dueAt: Date, hasTime: Bool, calendar: Calendar) -> Date {
        hasTime ? dueAt : calendar.startOfDay(for: dueAt).addingTimeInterval(86_400)
    }

    /// Mean completions across up to 4 trailing attribution windows that
    /// postdate the first eligible period; nil with no usable history.
    static func trailingAverage(
        stats: [CompletedTaskStat],
        windows: [Range<Date>],
        notBefore firstEligible: Date?
    ) -> Double? {
        let usable = windows.filter { window in
            guard let firstEligible else { return true }
            return window.lowerBound >= firstEligible
        }
        guard !usable.isEmpty else { return nil }
        let counts = usable.map { window in
            stats.filter { window.contains($0.completedAt) }.count
        }
        return Double(counts.reduce(0, +)) / Double(usable.count)
    }

    /// Whether any vacation interval overlaps the window, and whether the
    /// window is fully covered (fully covered periods compose nothing).
    static func vacationCoverage(
        intervals: [ObservationInterval], window: Range<Date>, now: Date
    ) -> (overlaps: Bool, fullyCovered: Bool) {
        let vacations = intervals
            .filter { $0.kind == .vacation }
            .map { $0.start..<($0.end ?? now) }
            .filter { $0.overlaps(window) }
        guard !vacations.isEmpty else { return (false, false) }
        // Full coverage by a single interval is the only realistic shape
        // (vacations are weeks, gaps between them are not seconds).
        let fully = vacations.contains { $0.lowerBound <= window.lowerBound && $0.upperBound >= window.upperBound }
        return (true, fully)
    }

    // MARK: - Beat facts

    /// The period's best day: max completions on one civil day, if ≥ 3.
    /// Uses the records' own completion-local dates (Feature 4's model).
    static func bestDay(stats: [CompletedTaskStat]) -> PeriodSummary.BestDay? {
        let byDay = Dictionary(grouping: stats, by: \.completedLocalDate)
        guard let (dateString, records) = byDay.max(by: {
            ($0.value.count, $1.key) < ($1.value.count, $0.key)
        }), records.count >= 3,
              let day = CivilDay(dateString)
        else { return nil }
        return PeriodSummary.BestDay(
            weekdayName: weekdayNames[day.weekday], count: records.count
        )
    }

    /// Streak milestones landed inside the window, reconstructed by
    /// walking the unbroken active-day chain back from the last active
    /// day. A chain broken mid-period stops the walk - never guess.
    static func milestonesLanded(
        stats: [CompletedTaskStat],
        window: Range<Date>,
        streakCount: Int,
        lastActiveDate: Date?,
        zone: TimeZone
    ) -> [Int] {
        guard streakCount > 0, let lastActiveDate else { return [] }
        let calendar = LetterSchedule.calendar(for: zone)
        let lastActive = CivilDay(of: lastActiveDate, in: calendar)
        let activeDays = Set(stats.map(\.completedLocalDate)).compactMap(CivilDay.init).sorted()
        guard !activeDays.isEmpty else { return [] }

        var milestones: [Int] = []
        var streak = streakCount
        var expected = lastActive
        for day in activeDays.reversed() {
            guard day == expected else {
                // Gap in the chain (or completions after lastActive):
                // stop rather than misattribute a milestone.
                if day < expected { break }
                continue
            }
            let instant = Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
            if window.lowerBound <= instant, instant < window.upperBound,
               StreakMilestones.isMilestone(streak) {
                milestones.append(streak)
            }
            streak -= 1
            expected = day.advanced(by: -1)
            if streak <= 0 { break }
        }
        return milestones.sorted()
    }

    /// The relationship anniversary whose date fell inside the window
    /// (Personal Layer, Feature 2). Date-only milestone math in the
    /// letter's authoritative zone; when two land in one period (not
    /// possible with the sparse v1 set, but the scan is honest) the
    /// larger, later mark wins. `duringVacation` marks a date the trip
    /// covered - the letter is the surface that remembers it.
    static func anniversary(
        adoptedOn: String?,
        window: Range<Date>,
        intervals: [ObservationInterval],
        now: Date,
        zone: TimeZone
    ) -> PeriodSummary.AnniversaryFact? {
        guard adoptedOn != nil else { return nil }
        let calendar = LetterSchedule.calendar(for: zone)
        let firstDay = CivilDay(of: window.lowerBound, in: calendar)
        // The window's exclusive end belongs to the next period's first
        // moment; step back one second before taking its civil day.
        let lastDay = CivilDay(of: window.upperBound.addingTimeInterval(-1), in: calendar)
        guard let milestone = AnniversaryCalendar.milestones(
            adoptedOn: adoptedOn, from: firstDay, through: lastDay
        ).last else { return nil }

        let midday = Date(
            timeIntervalSince1970: TimeInterval(milestone.day.dayNumber) * 86_400 + 43_200
        )
        let duringVacation = intervals.contains {
            $0.kind == .vacation && $0.contains(min(midday, now))
        }
        return PeriodSummary.AnniversaryFact(
            tier: milestone.tier, duringVacation: duringVacation
        )
    }

    /// The single biggest recovery: the overdue task cleared this window
    /// that had waited longest. Carries the title - full variant only.
    static func comeback(
        completedTasks: [TaskItem], window: Range<Date>, zone: TimeZone
    ) -> PeriodSummary.ComebackFact? {
        let calendar = LetterSchedule.calendar(for: zone)
        let events = completedTasks.compactMap { task -> (TaskItem, TimeInterval, Date)? in
            guard let completedAt = task.completedAt, window.contains(completedAt),
                  let dueAt = task.dueAt
            else { return nil }
            let boundary = overdueBoundary(dueAt: dueAt, hasTime: task.hasTime, calendar: calendar)
            let waited = completedAt.timeIntervalSince(boundary)
            guard waited > 0 else { return nil }
            return (task, waited, completedAt)
        }
        guard let biggest = events.max(by: { $0.1 < $1.1 }) else { return nil }
        let weekday = calendar.component(.weekday, from: biggest.2)
        return PeriodSummary.ComebackFact(
            taskTitle: biggest.0.title,
            completedWeekdayName: weekdayNames[weekday]
        )
    }
}
