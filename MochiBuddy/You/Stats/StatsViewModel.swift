//
//  StatsViewModel.swift
//  MochiBuddy
//
//  Streaks & stats - gentle momentum, not a scoreboard. Week strip and
//  charts come from completed-task timestamps; streak/coins from the
//  profile; the noticed lines and memory rows ride the Personal Layer's
//  existing engines (Features 4 and 2) without advancing their cadence.
//

import SwiftUI

final class StatsViewModel: StateViewModel<
    StatsBehavior.UIState,
    StatsBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let petIdentityStore: PetIdentityStore
    private let observationService: ObservationService?
    private let observationLedger: ObservationLedger?
    private let calendar: Calendar

    /// Per-range fetch cache - toggling ranges must not re-read Firestore
    /// for a window this screen already pulled.
    private var statsCache: [StatsBehavior.TimeRange: [CompletedTaskStat]] = [:]

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        petIdentityStore: PetIdentityStore,
        observationService: ObservationService? = nil,
        observationLedger: ObservationLedger? = nil,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.petIdentityStore = petIdentityStore
        self.observationService = observationService
        self.observationLedger = observationLedger
        self.calendar = calendar
        super.init(initialState: StatsBehavior.UIState())
    }

    override func triggerAsync(_ action: StatsBehavior.ViewAction) async {
        switch action {
        case .load:
            await load()

        case .rangeChanged(let range):
            guard range != uiState.range else { return }
            state.range = range
            await load()
        }
    }

    private func load() async {
        guard let userId = authRepository.currentAccount?.uid else { return }
        let now = Date.now

        var next = uiState
        next.petName = petIdentityStore.name

        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let streak = profile?.streakCount ?? 0
        let bestStreak = profile?.bestStreakCount ?? 0
        next.coins = profile?.coins ?? 0
        next.streakText = "\(streak) day\(streak == 1 ? "" : "s")"
        next.streakSub = streak > 0
            ? "Keep it going, a task a day does it"
            : "A task a day starts one"

        let range = next.range
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let rangeStart = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today

        // One range-scoped fetch feeds every card; the streak strip always
        // slices the last 7 days regardless of the selected window.
        let stats: [CompletedTaskStat]
        if let cached = statsCache[range] {
            stats = cached
        } else {
            stats = (try? await taskRepository.completedTaskStats(since: rangeStart, userId: userId)) ?? []
            statsCache[range] = stats
        }
        let weekStats = stats.filter { $0.completedAt >= weekStart }
        let lists = (try? await listRepository.fetchLists(userId: userId)) ?? []

        next.week = JournalTimeline.weekCells(stats: weekStats, weekStart: weekStart, calendar: calendar)
        next.tiles = Self.tiles(
            rangeDone: stats.count,
            rangeOnTime: Self.onTimeText(stats),
            range: range,
            bestStreak: bestStreak,
            coins: next.coins,
            adoptedOn: profile?.adoptedOn ?? petIdentityStore.adoptedOn,
            today: CivilDay(of: now, in: calendar)
        ) + [Self.effortTile(stats: stats)]

        // Daily bars stay readable up to a month; 3 months buckets by week.
        next.trendUnit = range == .threeMonths ? .week : .day
        next.trend = stats.isEmpty
            ? []
            : (range == .threeMonths
                ? Self.weeklyTrendPoints(stats: stats, start: rangeStart, weeks: range.days / 7, calendar: calendar)
                : JournalTimeline.trendPoints(stats: stats, start: rangeStart, calendar: calendar, days: range.days))
        // "busiest on Tuesdays" is deliberately gone (D9): Day by day
        // supersedes it, and it was computed on the device calendar rather
        // than the stored completion context.
        next.trendCaption = stats.isEmpty ? nil : "\(Self.onTimeText(stats)) on time"

        let bestHoursEntries = BestHours.entries(stats: stats)
        let histogram = BestHours.histogram(entries: bestHoursEntries)
        let weekdayRows = BestHours.weekdayRows(entries: bestHoursEntries, calendar: calendar)
        next.bestHours = Self.bestHoursCard(
            histogram: histogram, rows: weekdayRows, petName: next.petName, calendar: calendar
        )
        next.dayByDay = Self.dayByDayRows(weekdayRows, range: range, calendar: calendar)
        next.listBreakdown = Self.listSlices(stats: stats, lists: lists)

        next.noticedLines = await noticedLines(
            userId: userId, petName: next.petName, lists: lists, now: now
        )
        next.memoryRows = Self.memoryRows(facts: await Self.minedFacts(
            profile: profile, observationService: observationService, now: now, calendar: calendar
        ))

        setUIState(next)
    }

    // MARK: - Personal Layer readers

    /// Qualified observations rendered through the non-rotating peek -
    /// a read-only surface never advances rotation or cadence state
    /// (the Journal's live card owns that bookkeeping).
    private func noticedLines(
        userId: String, petName: String, lists: [TaskList], now: Date
    ) async -> [String] {
        guard let observationService, let observationLedger,
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return [] }
        let qualified = ObservationEngine.evaluate(inputs).qualified
        return qualified.prefix(3).compactMap { observation in
            var listName: String?
            if case .listReturn(let listId) = observation.conclusion {
                listName = lists.first { $0.id == listId }?.name
            }
            return observationLedger.peekLine(
                for: observation.conclusion, petName: petName, listName: listName, userId: userId
            )
        }
    }

    private static func minedFacts(
        profile: UserProfile?,
        observationService: ObservationService?,
        now: Date,
        calendar: Calendar
    ) async -> [CallbackFact] {
        guard let profile, let observationService,
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return [] }
        let miner = CallbackMinerInputs(
            records: inputs.records,
            adoptedOn: profile.adoptedOn,
            streakCount: profile.streakCount,
            bestStreakCount: profile.bestStreakCount,
            bestStreakAchievedOn: profile.bestStreakAchievedOn,
            lastActiveDay: profile.lastActiveDate.map { CivilDay(of: $0, in: calendar) }
        )
        return CallbackFactMiner.facts(miner, on: CivilDay(of: now, in: calendar))
    }

    // MARK: - Derivations (pure, testable)

    static func tiles(
        rangeDone: Int,
        rangeOnTime: String,
        range: StatsBehavior.TimeRange,
        bestStreak: Int,
        coins: Int,
        adoptedOn: String?,
        today: CivilDay
    ) -> [StatsBehavior.StatTile] {
        let (doneTitle, onTimeSubtitle): (String, String) = switch range {
        case .week: ("Done this week", "this week")
        case .month: ("Done this month", "this month")
        case .threeMonths: ("Done in 3 months", "3 months")
        }
        var tiles: [StatsBehavior.StatTile] = [
            .init(id: "done", value: "\(rangeDone)", title: doneTitle, subtitle: "tasks"),
            .init(id: "completion", value: rangeOnTime, title: "On time", subtitle: onTimeSubtitle),
            .init(id: "best", value: "\(bestStreak)", title: "Best streak", subtitle: bestStreak == 1 ? "day" : "days"),
        ]
        // The fourth tile prefers the friendship; coins fill in until an
        // adoption date exists (pre-Feature-1 profiles).
        if let adoptedOn, let adopted = CivilDay(adoptedOn), adopted <= today {
            let days = today.dayNumber - adopted.dayNumber + 1
            tiles.append(.init(
                id: "together", value: "\(days)", title: days == 1 ? "Day together" : "Days together",
                subtitle: "since \(shortDate(adopted))"
            ))
        } else {
            tiles.append(.init(id: "coins", value: "\(coins)", title: "Coins", subtitle: "balance"))
        }
        return tiles
    }

    /// The Effort tile (effort guide §7): summed nominal minutes rounded
    /// to the nearest half hour and shown approximate - the levels are
    /// coarse, so to-the-minute would be false precision. Coverage lives
    /// in the subtitle ("12 of 34 rated") so a floor can never mislead;
    /// "–" only when nothing in the range carries an effort, matching
    /// onTimeText. Recurring completions ARE included (D12): a daily
    /// 30-minute workout is real time spent.
    static func effortTile(stats: [CompletedTaskStat]) -> StatsBehavior.StatTile {
        let rated = stats.compactMap(\.estimatedMinutes)
        guard !rated.isEmpty else {
            return .init(id: "effort", value: "–", title: "Effort", subtitle: "nothing rated yet")
        }
        let rounded = max(30, 30 * Int((Double(rated.reduce(0, +)) / 30).rounded()))
        let hours = rounded / 60
        let minutes = rounded % 60
        let text = switch (hours, minutes) {
        case (0, _): "~\(minutes)m"
        case (_, 0): "~\(hours)h"
        default: "~\(hours)h \(minutes)m"
        }
        return .init(
            id: "effort", value: text, title: "Effort",
            subtitle: "\(rated.count) of \(stats.count) rated"
        )
    }

    /// Weekly buckets for the 3-month trend - each point's `day` is that
    /// civil week's start date, counts summed across the week.
    static func weeklyTrendPoints(
        stats: [CompletedTaskStat],
        start: Date,
        weeks: Int,
        calendar: Calendar
    ) -> [StatsBehavior.TrendPoint] {
        var countsByDay: [Date: Int] = [:]
        for stat in stats {
            countsByDay[calendar.startOfDay(for: stat.completedAt), default: 0] += 1
        }
        return (0..<weeks).compactMap { week in
            guard let weekStart = calendar.date(byAdding: .day, value: week * 7, to: start) else { return nil }
            let count = (0..<7).reduce(0) { sum, offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return sum }
                return sum + (countsByDay[day] ?? 0)
            }
            return StatsBehavior.TrendPoint(id: week, day: weekStart, count: count)
        }
    }

    static func onTimeText(_ stats: [CompletedTaskStat]) -> String {
        guard !stats.isEmpty else { return "–" }
        // No due date counts as on time - undated tasks can't be late.
        let onTime = stats.filter { stat in
            guard let due = stat.dueAt else { return true }
            return stat.completedAt <= due
        }.count
        return "\(Int((Double(onTime) / Double(stats.count) * 100).rounded()))%"
    }

    /// The "Your best hours" card - nil until any completion exists (D1).
    static func bestHoursCard(
        histogram: BestHours.Histogram,
        rows: [BestHours.WeekdayRow],
        petName: String,
        calendar: Calendar
    ) -> StatsBehavior.BestHoursCard? {
        guard let peakStart = histogram.peakStart else { return nil }
        let inPeak = Set((0..<3).map { (peakStart + $0) % 24 })
        return StatsBehavior.BestHoursCard(
            bars: histogram.buckets.enumerated().map { bucket, count in
                .init(id: bucket, count: count, inPeak: inPeak.contains(bucket))
            },
            peakText: BestHours.peakRangeLabel(start: peakStart),
            inWindowText: "\(Int((histogram.inWindowShare * 100).rounded()))%",
            caption: BestHours.caption(
                histogram: histogram, rows: rows, petName: petName, calendar: calendar
            )
        )
    }

    /// "Day by day" rows as axis fractions. Empty until a row earns its
    /// capsule (D1's ladder) and always empty on the Week range (D6) -
    /// a box plot over at most one sample per row is a lie.
    static func dayByDayRows(
        _ rows: [BestHours.WeekdayRow],
        range: StatsBehavior.TimeRange,
        calendar: Calendar
    ) -> [StatsBehavior.WeekdayRowUI] {
        guard range != .week, rows.contains(where: { $0.qualifies }) else { return [] }
        func fraction(_ minute: Int?) -> Double? {
            minute.map { Double($0) / 1440 }
        }
        return rows.map { row in
            .init(
                id: row.weekday,
                label: calendar.shortStandaloneWeekdaySymbols[row.weekday - 1],
                first: fraction(row.qualifies ? row.first : nil),
                last: fraction(row.qualifies ? row.last : nil),
                q1: fraction(row.q1),
                q3: fraction(row.q3),
                typical: fraction(row.typical),
                timeText: row.typical.map(BestHours.timeLabel(axisMinute:))
            )
        }
    }

    static func listSlices(
        stats: [CompletedTaskStat],
        lists: [TaskList],
        limit: Int = 5
    ) -> [StatsBehavior.ListSlice] {
        guard !stats.isEmpty else { return [] }
        var countsByList: [String?: Int] = [:]
        for stat in stats {
            countsByList[stat.listId, default: 0] += 1
        }
        let slices = countsByList
            .map { listId, count -> StatsBehavior.ListSlice in
                if let listId, let list = lists.first(where: { $0.id == listId }) {
                    return .init(id: listId, name: list.name, color: Color(hexString: list.colorHex), count: count)
                }
                // Unknown ids (deleted lists) fold into the Inbox slice's look.
                return .init(
                    id: listId ?? "inbox",
                    name: listId == nil ? "Inbox" : "Former list",
                    color: Color(hexString: TaskListDefaults.colorChoices[0]),
                    count: count
                )
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        guard slices.count > limit else { return slices }
        let top = Array(slices.prefix(limit))
        let otherCount = slices.dropFirst(limit).reduce(0) { $0 + $1.count }
        return top + [.init(id: "other", name: "Other", color: .gray, count: otherCount)]
    }

    /// Mined facts as factual rows. Counts appear only in the families
    /// that permit them (best day, date echo); recovery stays digit-free
    /// by the same rule its rundown copy follows.
    static func memoryRows(facts: [CallbackFact]) -> [StatsBehavior.MemoryRow] {
        facts.compactMap { fact in
            switch fact.type {
            case .dateEcho:
                return .init(
                    id: fact.factId,
                    icon: "calendar",
                    title: fact.monthsBack == 1
                        ? "One month ago today"
                        : "\(fact.monthsBack) months ago today",
                    subtitle: "\(fact.count) task\(fact.count == 1 ? "" : "s") done on \(shortDate(fact.sourceDay))"
                )
            case .recovery:
                return .init(
                    id: fact.factId,
                    icon: "arrow.uturn.up",
                    title: "A quick comeback",
                    subtitle: "Slipped things got caught up in a hurry"
                )
            case .bestDay:
                return .init(
                    id: fact.factId,
                    icon: "sparkles",
                    title: fact.tied ? "One of your biggest days" : "Your biggest day yet",
                    subtitle: "\(fact.count) task\(fact.count == 1 ? "" : "s") on \(shortDate(fact.sourceDay))"
                )
            case .streakEra:
                return .init(
                    id: fact.factId,
                    icon: "flame.fill",
                    title: "Longest streak",
                    subtitle: fact.eraDated
                        ? "\(fact.streakCount) days · set \(shortDate(fact.sourceDay))"
                        : "\(fact.streakCount) days"
                )
            }
        }
    }

    /// "Jul 8" (or "Jul 8, 2025" once the year differs) from a civil day -
    /// zone-free, same doctrine as AdoptedOnDate's display.
    static func shortDate(_ day: CivilDay, today: CivilDay = CivilDay(of: .now, in: .current)) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        let anchor = Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
        let sameYear = utc.component(.year, from: anchor)
            == utc.component(.year, from: Date(timeIntervalSince1970: TimeInterval(today.dayNumber) * 86_400 + 43_200))
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: anchor)
    }
}
