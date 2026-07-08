//
//  TasksViewModelTests.swift
//  MochiBuddyTests
//
//  The four task surfaces: Today's pinned overdue, Upcoming's day groups,
//  the Lists overview counts, and Done's celebration — plus toggling
//  between them.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeTasksVM(
    incomplete: [TaskItem] = [],
    completed: [TaskItem] = [],
    lists: [TaskList] = [],
    profile: UserProfile = makeProfile(coins: 128, streak: 4)
) -> (TasksViewModel, StubTaskRepository, StubProfileRepository) {
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = incomplete
    taskRepo.completed = completed
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    let vm = TasksViewModel(
        authRepository: StubAuthRepository(),
        taskRepository: taskRepo,
        listRepository: listRepo,
        profileRepository: profileRepo,
        completionStore: TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo)
        )
    )
    return (vm, taskRepo, profileRepo)
}

private let calendar = Calendar.current
private var startOfToday: Date { calendar.startOfDay(for: .now) }
private func daysFromNow(_ d: Int) -> Date { calendar.date(byAdding: .day, value: d, to: startOfToday)! }

@Suite("TasksViewModel · Today")
@MainActor
struct TasksTodayTests {

    @Test("overdue pins to the top with a danger group; today follows")
    func overduePinned() async {
        let overdue = makeTask(id: "o1", dueAt: Date.now.addingTimeInterval(-30 * 3600), hasTime: true)
        let today = makeTask(id: "d1", dueAt: startOfToday)
        let (vm, _, _) = makeTasksVM(incomplete: [today, overdue])
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.groups.count == 2)
        let first = vm.uiState.groups[0]
        #expect(first.label == "Overdue")
        #expect(first.isDanger)
        #expect(first.count == 1)
        #expect(first.items.map(\.id) == ["o1"])
        let second = vm.uiState.groups[1]
        #expect(second.label == "Today")
        #expect(second.items.map(\.id) == ["d1"])
    }

    @Test("undated and future tasks stay off the Today segment")
    func todayScopeExcludes() async {
        let undated = makeTask(id: "u")
        let future = makeTask(id: "f", dueAt: daysFromNow(2))
        let today = makeTask(id: "t", dueAt: startOfToday)
        let (vm, _, _) = makeTasksVM(incomplete: [undated, future, today])
        await vm.triggerAsync(.refresh)
        let ids = vm.uiState.groups.flatMap { $0.items.map(\.id) }
        #expect(ids == ["t"])
    }

    @Test("nothing due and nothing done today → the calm empty state")
    func calmEmpty() async {
        let (vm, _, _) = makeTasksVM(incomplete: [makeTask(dueAt: daysFromNow(3))])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.showEmptyCalm == true)
        #expect(vm.uiState.showAllCaughtUp == false)
    }

    @Test("nothing due but completions today → the celebration state")
    func allCaughtUp() async {
        let done = makeTask(id: "d", completed: true, completedAt: .now)
        let (vm, _, _) = makeTasksVM(completed: [done])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.showAllCaughtUp == true)
        #expect(vm.uiState.showEmptyCalm == false)
        #expect(vm.uiState.streakDays == 4)
    }

    @Test("yesterday's completions alone don't celebrate today")
    func staleCompletionsDontCelebrate() async {
        let done = makeTask(completed: true, completedAt: daysFromNow(-1))
        let (vm, _, _) = makeTasksVM(completed: [done])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.showEmptyCalm == true)
        #expect(vm.uiState.showAllCaughtUp == false)
    }
}

@Suite("TasksViewModel · Upcoming")
@MainActor
struct TasksUpcomingTests {

    @Test("groups land in day order: Tomorrow, weekdays, Later, Someday")
    func grouping() async {
        let tomorrow = makeTask(id: "tm", dueAt: daysFromNow(1))
        let plus3 = makeTask(id: "p3", dueAt: daysFromNow(3))
        let plus10 = makeTask(id: "p10", dueAt: daysFromNow(10))
        let someday = makeTask(id: "sd")
        let (vm, _, _) = makeTasksVM(incomplete: [someday, plus10, plus3, tomorrow])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.upcoming))

        let groups = vm.uiState.groups
        #expect(groups.map(\.id) == ["d1", "d3", "later", "someday"])
        #expect(groups[0].label.hasPrefix("Tomorrow"))
        let weekdayName = daysFromNow(3).formatted(.dateTime.weekday(.wide))
        #expect(groups[1].label == weekdayName)
        #expect(groups[2].items.map(\.id) == ["p10"])
        #expect(groups[3].items.map(\.id) == ["sd"])
    }

    @Test("today's and overdue tasks never leak into Upcoming")
    func noLeakage() async {
        let overdue = makeTask(id: "o", dueAt: Date.now.addingTimeInterval(-3600), hasTime: true)
        let today = makeTask(id: "t", dueAt: startOfToday)
        let tomorrow = makeTask(id: "tm", dueAt: daysFromNow(1))
        let (vm, _, _) = makeTasksVM(incomplete: [overdue, today, tomorrow])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.upcoming))
        let ids = vm.uiState.groups.flatMap { $0.items.map(\.id) }
        #expect(ids == ["tm"])
    }

    @Test("future rows read the weekday and 'all day' for date-only tasks")
    func futureMeta() async {
        let tomorrow = makeTask(id: "tm", dueAt: daysFromNow(1))
        let (vm, _, _) = makeTasksVM(incomplete: [tomorrow])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.upcoming))
        let item = vm.uiState.groups[0].items[0]
        #expect(item.meta.contains("all day"))
        #expect(item.state == .normal)
    }
}

@Suite("TasksViewModel · Done & Lists")
@MainActor
struct TasksDoneAndListsTests {

    @Test("Done groups by Today / Yesterday / Earlier and celebrates the coins")
    func doneGroups() async {
        let today = makeTask(id: "a", completed: true, completedAt: .now)
        let yesterday = makeTask(id: "b", completed: true, completedAt: daysFromNow(-1).addingTimeInterval(3600))
        let lastWeek = makeTask(id: "c", completed: true, completedAt: daysFromNow(-6))
        let (vm, _, _) = makeTasksVM(completed: [today, yesterday, lastWeek])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.done))

        #expect(vm.uiState.groups.map(\.label) == ["Today", "Yesterday", "Earlier"])
        #expect(vm.uiState.doneCelebration == "Earned +30 coins from these")
        #expect(vm.uiState.subtitle == "3 done this week")
        #expect(vm.uiState.groups[0].items[0].state == .done)
        #expect(vm.uiState.groups[0].items[0].chip == "Done")
    }

    @Test("Lists counts open tasks per list, with the implicit Inbox first")
    func listCounts() async {
        let lists = [
            TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "💼", order: 0),
            TaskList(id: "health", name: "Health", colorHex: "#9BE6B4", icon: "💪", order: 1),
        ]
        let tasks = [
            makeTask(listId: nil),
            makeTask(listId: nil),
            makeTask(listId: "work"),
            makeTask(listId: "work", completed: false),
            makeTask(listId: "health"),
        ]
        let (vm, _, _) = makeTasksVM(incomplete: tasks, lists: lists)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.lists))

        let rows = vm.uiState.listItems
        #expect(rows.map(\.id) == ["inbox", "work", "health"])
        #expect(rows[0].countText == "2 open tasks")
        #expect(rows[1].countText == "2 open tasks")
        #expect(rows[2].countText == "1 open task", "singular form for one task")
    }

    @Test("checking off in Today moves the task into Done; unchecking brings it back")
    func toggleRoundTrip() async {
        let task = makeTask(id: "t1", dueAt: startOfToday)
        let (vm, _, _) = makeTasksVM(incomplete: [task], profile: makeProfile(coins: 0))
        await vm.triggerAsync(.refresh)

        await vm.triggerAsync(.toggleTask("t1"))
        #expect(vm.uiState.coins == RewardsStore.coinsPerTask)
        await vm.triggerAsync(.selectSegment(.done))
        #expect(vm.uiState.groups.flatMap { $0.items.map(\.id) } == ["t1"])

        await vm.triggerAsync(.toggleTask("t1"))
        #expect(vm.uiState.coins == 0, "clawback on undo")
        await vm.triggerAsync(.selectSegment(.today))
        #expect(vm.uiState.groups.flatMap { $0.items.map(\.id) } == ["t1"])
    }

    @Test("due-soon rows warn: timed task within three hours reads 'Due soon' with the Soon chip")
    func dueSoonMeta() async {
        let soon = makeTask(id: "s", dueAt: Date.now.addingTimeInterval(30 * 60), hasTime: true)
        let (vm, _, _) = makeTasksVM(incomplete: [soon])
        await vm.triggerAsync(.refresh)
        // Guard against runs right before midnight where +30min crosses days.
        guard calendar.isDate(soon.dueAt!, inSameDayAs: .now) else { return }
        let item = vm.uiState.groups.flatMap(\.items).first { $0.id == "s" }!
        #expect(item.state == .due)
        #expect(item.meta.hasPrefix("Due soon"))
        #expect(item.chip == "Soon")
    }
}
