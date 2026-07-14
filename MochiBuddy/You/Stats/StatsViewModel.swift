//
//  StatsViewModel.swift
//  MochiBuddy
//
//  Streaks & stats — gentle momentum, not a scoreboard. Week strip and
//  tiles come from completed-task timestamps; streak/coins from the profile.
//

import SwiftUI

final class StatsViewModel: StateViewModel<
    StatsBehavior.UIState,
    StatsBehavior.ViewAction
> {

    /// The charts read four weeks of completions.
    static let trendDays = 28

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        super.init(initialState: StatsBehavior.UIState())
    }

    override func triggerAsync(_ action: StatsBehavior.ViewAction) async {
        switch action {
        case .load:
            await load()
        }
    }

    private func load() async {
        guard let userId = authRepository.currentAccount?.uid else { return }

        var next = uiState

        var streak = 0
        var bestStreak = 0
        if let profile = try? await profileRepository.fetchProfile(userId: userId) {
            next.coins = profile.coins
            streak = profile.streakCount
            bestStreak = profile.bestStreakCount
        }
        next.streakText = "\(streak) day\(streak == 1 ? "" : "s")"
        next.streakSub = streak > 0
            ? "Keep it going — a task a day does it"
            : "A task a day starts one"

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let trendStart = calendar.date(byAdding: .day, value: -(Self.trendDays - 1), to: today) ?? today

        // One 4-week fetch feeds everything; week widgets slice the last 7.
        let stats = (try? await taskRepository.completedTaskStats(since: trendStart, userId: userId)) ?? []
        let weekStats = stats.filter { $0.completedAt >= weekStart }
        let lists = (try? await listRepository.fetchLists(userId: userId)) ?? []

        next.week = Self.weekCells(stats: weekStats, weekStart: weekStart, calendar: calendar)

        let doneThisWeek = weekStats.count
        next.tiles = [
            .init(id: "done", value: "\(doneThisWeek)", title: "Done this week", subtitle: "tasks"),
            .init(id: "completion", value: Self.onTimeText(weekStats), title: "Completion", subtitle: "on time"),
            .init(id: "coins", value: "\(next.coins)", title: "Coins", subtitle: "balance"),
            .init(id: "best", value: "\(bestStreak)", title: "Best streak", subtitle: bestStreak == 1 ? "day" : "days"),
        ]

        next.trend = Self.trendPoints(stats: stats, start: trendStart, calendar: calendar)
        next.onTimeText = Self.onTimeText(stats)
        next.busiestWeekdayText = Self.busiestWeekday(stats: stats, calendar: calendar) ?? "—"
        next.trendCaption = stats.isEmpty
            ? nil
            : "\(Self.onTimeText(stats)) on time · busiest on \(next.busiestWeekdayText)s"
        next.listBreakdown = Self.listSlices(stats: stats, lists: lists)

        setUIState(next)
    }

    // MARK: - Chart derivations (pure, testable)

    static func onTimeText(_ stats: [CompletedTaskStat]) -> String {
        guard !stats.isEmpty else { return "—" }
        // No due date counts as on time — undated tasks can't be late.
        let onTime = stats.filter { stat in
            guard let due = stat.dueAt else { return true }
            return stat.completedAt <= due
        }.count
        return "\(Int((Double(onTime) / Double(stats.count) * 100).rounded()))%"
    }

    static func trendPoints(
        stats: [CompletedTaskStat],
        start: Date,
        calendar: Calendar
    ) -> [StatsBehavior.TrendPoint] {
        var countsByDay: [Date: Int] = [:]
        for stat in stats {
            countsByDay[calendar.startOfDay(for: stat.completedAt), default: 0] += 1
        }
        return (0..<trendDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return StatsBehavior.TrendPoint(id: offset, day: day, count: countsByDay[day] ?? 0)
        }
    }

    static func busiestWeekday(stats: [CompletedTaskStat], calendar: Calendar) -> String? {
        guard !stats.isEmpty else { return nil }
        var countsByWeekday: [Int: Int] = [:]
        for stat in stats {
            countsByWeekday[calendar.component(.weekday, from: stat.completedAt), default: 0] += 1
        }
        guard let busiest = countsByWeekday.max(by: {
            ($0.value, $1.key) < ($1.value, $0.key) // ties break to the earlier weekday
        })?.key else { return nil }
        return calendar.standaloneWeekdaySymbols[busiest - 1]
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

    private static func weekCells(
        stats: [CompletedTaskStat],
        weekStart: Date,
        calendar: Calendar
    ) -> [StatsBehavior.DayCell] {
        var countsByDay: [Date: Int] = [:]
        for stat in stats {
            let day = calendar.startOfDay(for: stat.completedAt)
            countsByDay[day, default: 0] += 1
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE" // narrow weekday — "M", "T", …

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            let count = countsByDay[day] ?? 0
            return StatsBehavior.DayCell(
                id: offset,
                dayLetter: formatter.string(from: day),
                count: count,
                level: min(count, 3)
            )
        }
    }
}
