//
//  StatsViewModel.swift
//  MochiBuddy
//
//  Streaks & stats — gentle momentum, not a scoreboard. Week strip and
//  tiles come from completed-task timestamps; streak/coins from the profile.
//

import Foundation

final class StatsViewModel: StateViewModel<
    StatsBehavior.UIState,
    StatsBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
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
        let stats = (try? await taskRepository.completedTaskStats(since: weekStart, userId: userId)) ?? []

        next.week = Self.weekCells(stats: stats, weekStart: weekStart, calendar: calendar)

        let doneThisWeek = stats.count
        let onTime = stats.filter { stat in
            guard let due = stat.dueAt else { return true }
            return stat.completedAt <= due
        }.count
        let completionText = doneThisWeek == 0
            ? "—"
            : "\(Int((Double(onTime) / Double(doneThisWeek) * 100).rounded()))%"

        next.tiles = [
            .init(id: "done", value: "\(doneThisWeek)", title: "Done this week", subtitle: "tasks"),
            .init(id: "completion", value: completionText, title: "Completion", subtitle: "on time"),
            .init(id: "coins", value: "\(next.coins)", title: "Coins", subtitle: "balance"),
            .init(id: "best", value: "\(bestStreak)", title: "Best streak", subtitle: bestStreak == 1 ? "day" : "days"),
        ]

        setUIState(next)
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
