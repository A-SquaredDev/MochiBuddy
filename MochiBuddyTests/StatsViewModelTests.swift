//
//  StatsViewModelTests.swift
//  MochiBuddyTests
//
//  The chart derivations: 4-week trend fill, on-time math, busiest
//  weekday, and the per-list breakdown.
//

import Foundation
import Testing
@testable import MochiBuddy

private let calendar = Calendar.current
private var startOfToday: Date { calendar.startOfDay(for: .now) }
private func daysAgo(_ d: Int) -> Date { calendar.date(byAdding: .day, value: -d, to: startOfToday)! }

@MainActor
private func makeStatsVM(
    stats: [CompletedTaskStat] = [],
    lists: [TaskList] = [],
    profile: UserProfile = makeProfile(coins: 40, streak: 3, bestStreak: 9)
) -> StatsViewModel {
    let taskRepo = StubTaskRepository()
    taskRepo.completedStats = stats
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    return StatsViewModel(
        authRepository: StubAuthRepository(),
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        listRepository: listRepo
    )
}

@Suite("Stats · trend")
@MainActor
struct StatsTrendTests {

    @Test("the trend is 28 zero-filled daily points with counts on seeded days")
    func trendFill() async {
        let stats = [
            CompletedTaskStat(completedAt: startOfToday.addingTimeInterval(3600), dueAt: nil),
            CompletedTaskStat(completedAt: startOfToday.addingTimeInterval(7200), dueAt: nil),
            CompletedTaskStat(completedAt: daysAgo(3).addingTimeInterval(3600), dueAt: nil),
        ]
        let vm = makeStatsVM(stats: stats)
        await vm.triggerAsync(.load)

        let trend = vm.uiState.trend
        #expect(trend.count == StatsViewModel.trendDays)
        #expect(trend.last?.count == 2, "today is the last point")
        #expect(trend[trend.count - 4].count == 1, "three days ago")
        #expect(trend.map(\.count).reduce(0, +) == 3, "every other day is zero")
    }

    @Test("week tiles only count the last 7 days even though the fetch spans 28")
    func weekTilesSliceSeven() async {
        let stats = [
            CompletedTaskStat(completedAt: daysAgo(1), dueAt: nil),
            CompletedTaskStat(completedAt: daysAgo(10), dueAt: nil),
            CompletedTaskStat(completedAt: daysAgo(20), dueAt: nil),
        ]
        let vm = makeStatsVM(stats: stats)
        await vm.triggerAsync(.load)
        let doneTile = vm.uiState.tiles.first { $0.id == "done" }
        #expect(doneTile?.value == "1")
        #expect(vm.uiState.trend.map(\.count).reduce(0, +) == 3)
    }

    @Test("on-time math: undated counts on-time, late counts against")
    func onTimeMath() {
        let due = startOfToday
        let stats = [
            CompletedTaskStat(completedAt: due.addingTimeInterval(-3600), dueAt: due),  // on time
            CompletedTaskStat(completedAt: due.addingTimeInterval(3600), dueAt: due),   // late
            CompletedTaskStat(completedAt: due, dueAt: nil),                            // undated → on time
            CompletedTaskStat(completedAt: due, dueAt: nil),                            // undated → on time
        ]
        #expect(StatsViewModel.onTimeText(stats) == "75%")
        #expect(StatsViewModel.onTimeText([]) == "–")
    }

    @Test("busiest weekday names the weekday with the most completions")
    func busiestWeekday() {
        // Two completions on today's weekday, one on yesterday's.
        let stats = [
            CompletedTaskStat(completedAt: startOfToday, dueAt: nil),
            CompletedTaskStat(completedAt: daysAgo(7), dueAt: nil),
            CompletedTaskStat(completedAt: daysAgo(1), dueAt: nil),
        ]
        let expected = calendar.standaloneWeekdaySymbols[calendar.component(.weekday, from: startOfToday) - 1]
        #expect(StatsViewModel.busiestWeekday(stats: stats, calendar: calendar) == expected)
        #expect(StatsViewModel.busiestWeekday(stats: [], calendar: calendar) == nil)
    }
}

@Suite("Stats · list breakdown")
@MainActor
struct StatsListBreakdownTests {

    private let work = TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0)

    @Test("slices map listIds to names, bucket nil as Inbox, and sort by count")
    func slices() {
        let stats = [
            CompletedTaskStat(completedAt: .now, dueAt: nil, listId: "work"),
            CompletedTaskStat(completedAt: .now, dueAt: nil, listId: "work"),
            CompletedTaskStat(completedAt: .now, dueAt: nil, listId: nil),
        ]
        let slices = StatsViewModel.listSlices(stats: stats, lists: [work])
        #expect(slices.map(\.name) == ["Work", "Inbox"])
        #expect(slices.map(\.count) == [2, 1])
    }

    @Test("beyond the limit, the tail folds into a single Other slice")
    func otherFold() {
        let stats = (0..<7).flatMap { index in
            Array(repeating: CompletedTaskStat(completedAt: .now, dueAt: nil, listId: "l\(index)"), count: 7 - index)
        }
        let lists = (0..<7).map {
            TaskList(id: "l\($0)", name: "List \($0)", colorHex: "#C9A6FF", icon: "tag.fill", order: $0)
        }
        let slices = StatsViewModel.listSlices(stats: stats, lists: lists, limit: 5)
        #expect(slices.count == 6)
        #expect(slices.last?.name == "Other")
        #expect(slices.last?.count == 2 + 1, "the two smallest lists fold together")
    }

    @Test("a completion whose list was deleted still shows, labeled as a former list")
    func deletedList() {
        let stats = [CompletedTaskStat(completedAt: .now, dueAt: nil, listId: "gone")]
        let slices = StatsViewModel.listSlices(stats: stats, lists: [])
        #expect(slices.first?.name == "Former list")
    }
}
