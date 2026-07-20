//
//  TasksViewModelTests.swift
//  MochiBuddyTests
//
//  The four task surfaces: Today's pinned overdue, Upcoming's day groups,
//  the Lists overview counts, and Done's celebration - plus toggling
//  between them.
//

import Foundation
import Testing
@testable import MochiBuddy

/// A blank, test-scoped UserDefaults so celebration-dismissal state never
/// leaks between tests (or into the app's real defaults).
private func makeTestDefaults() -> UserDefaults {
    let suiteName = "TasksVMTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func makeTasksVM(
    incomplete: [TaskItem] = [],
    completed: [TaskItem] = [],
    lists: [TaskList] = [],
    profile: UserProfile = makeProfile(coins: 128, streak: 4),
    reminders: StubRemindersGateway = StubRemindersGateway(),
    defaults: UserDefaults = makeTestDefaults()
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
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: MembershipSession()
        ),
        remindersGateway: reminders,
        membershipSession: MembershipSession(),
        recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
        relay: StubRelay(),
        defaults: defaults
    )
    return (vm, taskRepo, profileRepo)
}

private let calendar = Calendar.current
private var startOfToday: Date { calendar.startOfDay(for: .now) }
private func daysFromNow(_ d: Int) -> Date { calendar.date(byAdding: .day, value: d, to: startOfToday)! }

@Suite("TasksViewModel · loading")
@MainActor
struct TasksLoadingTests {

    @Test("skeleton shows until the first refresh lands")
    func loadingClearsAfterRefresh() async {
        let (vm, _, _) = makeTasksVM(incomplete: [makeTask(id: "t1", dueAt: startOfToday)])
        #expect(vm.uiState.isLoading == true)
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.isLoading == false)
    }
}

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

    @Test("rows beyond next week show their real date, so a repeat advancing a week is visible")
    func laterMetaShowsDate() async {
        let farOut = makeTask(id: "far", dueAt: daysFromNow(10))
        let (vm, _, _) = makeTasksVM(incomplete: [farOut])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.upcoming))
        let item = vm.uiState.groups.flatMap(\.items).first { $0.id == "far" }!
        let expected = daysFromNow(10).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        #expect(item.meta.contains(expected), "was \(item.meta)")
    }

    @Test("undoing a recurring completion removes the spawned occurrence from Upcoming")
    func undoReapsSpawnFromUpcoming() async {
        let friday = makeTask(id: "t1", dueAt: daysFromNow(3), repeatRule: .weekly)
        let (vm, taskRepo, _) = makeTasksVM(incomplete: [friday])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.upcoming))

        // Complete ahead of time: the row is replaced by next week's occurrence.
        await vm.triggerAsync(.toggleTask("t1"))
        let idsAfterComplete = vm.uiState.groups.flatMap { $0.items.map(\.id) }
        #expect(idsAfterComplete == [taskRepo.nextAddedTaskId])

        // Undo from anywhere: the premature spawn disappears, the original returns.
        await vm.triggerAsync(.toggleTask("t1"))
        let idsAfterUndo = vm.uiState.groups.flatMap { $0.items.map(\.id) }
        #expect(idsAfterUndo == ["t1"], "the reaped spawn must not linger as a duplicate")
        #expect(taskRepo.deletedIds == [taskRepo.nextAddedTaskId])
    }
}

@Suite("TasksViewModel · Apple Reminders")
@MainActor
struct TasksRemindersTests {

    private func makeSyncedSetup(
        reminderDueAt: Date? = nil,
        access: RemindersAccess = .granted
    ) -> (TasksViewModel, StubRemindersGateway, StubProfileRepository) {
        let gateway = StubRemindersGateway()
        gateway.access = access
        gateway.lists = [ReminderList(id: "ek-list", name: "Groceries", incompleteCount: 1, colorHex: "#8FD3F4")]
        gateway.openReminders = [
            makeReminder(id: "r1", title: "Buy oat milk", dueAt: reminderDueAt)
        ]
        let (vm, _, profileRepo) = makeTasksVM(
            profile: makeProfile(coins: 0, importedReminderListIds: ["ek-list"]),
            reminders: gateway
        )
        return (vm, gateway, profileRepo)
    }

    @Test("synced reminders appear in Today with ek: ids and the Reminders badge")
    func remindersInToday() async {
        let (vm, _, _) = makeSyncedSetup(reminderDueAt: startOfToday)
        await vm.triggerAsync(.refresh)
        let items = vm.uiState.groups.flatMap(\.items)
        let row = try! #require(items.first { $0.id == "ek:r1" })
        #expect(row.sourceBadge == "Reminders")
        #expect(row.listName == "Groceries")
        #expect(row.title == "Buy oat milk")
    }

    @Test("undated reminders land in Upcoming's Someday bucket")
    func remindersInUpcoming() async {
        let (vm, _, _) = makeSyncedSetup(reminderDueAt: nil)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.upcoming))
        let someday = try! #require(vm.uiState.groups.first { $0.id == "someday" })
        #expect(someday.items.map(\.id) == ["ek:r1"])
    }

    @Test("checking off a reminder writes to EventKit and never pays coins")
    func reminderToggleNoCoins() async {
        let (vm, gateway, profileRepo) = makeSyncedSetup(reminderDueAt: startOfToday)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("ek:r1"))

        #expect(gateway.setCompletedCalls.map(\.id) == ["r1"])
        #expect(gateway.setCompletedCalls.first?.completed == true)
        #expect(profileRepo.coinDeltas.isEmpty, "reminders never touch the coin economy")
        // The flipped row stays visible as done for the session.
        let doneGroup = try! #require(vm.uiState.groups.first { $0.id == "doneToday" })
        #expect(doneGroup.items.map(\.id) == ["ek:r1"])
        // But the honest coin banner ignores it.
        await vm.triggerAsync(.selectSegment(.done))
        #expect(vm.uiState.doneCelebration == nil)
    }

    @Test("a failed EventKit save reverts the optimistic flip")
    func reminderToggleRevertsOnFailure() async {
        let (vm, gateway, _) = makeSyncedSetup(reminderDueAt: startOfToday)
        gateway.setCompletedResult = false
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("ek:r1"))
        let items = vm.uiState.groups.flatMap(\.items)
        let row = try! #require(items.first { $0.id == "ek:r1" })
        #expect(row.state != .done)
    }

    @Test("reminder rows never open the task editor")
    func reminderRowsNotEditable() async {
        let (vm, _, _) = makeSyncedSetup(reminderDueAt: startOfToday)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.taskTapped("ek:r1"))
        #expect(vm.uiState.editingTask == nil)
    }

    @Test("synced Apple lists join the Lists overview with a badge and open count")
    func reminderListsRows() async {
        let (vm, _, _) = makeSyncedSetup(reminderDueAt: startOfToday)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.lists))
        let row = try! #require(vm.uiState.listItems.first { $0.id == "ek:ek-list" })
        #expect(row.name == "Groceries")
        #expect(row.badge == "Reminders")
        #expect(row.countText == "1 open task")
        #expect(vm.uiState.remindersAccessHint == nil)
    }

    @Test("revoked access hides reminder rows and surfaces the hint")
    func deniedAccessHint() async {
        let (vm, _, _) = makeSyncedSetup(reminderDueAt: startOfToday, access: .denied)
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.groups.flatMap(\.items).isEmpty)
        let hint = try! #require(vm.uiState.remindersAccessHint)
        #expect(hint.contains("Settings"))
    }

    @Test("tapping a synced Apple list navigates to its read-only detail")
    func reminderListNavigation() async {
        let (vm, _, _) = makeSyncedSetup(reminderDueAt: startOfToday)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.listTapped("ek:ek-list"))
        await recorder.drain()
        guard case .showListDetail(.reminders(let listId, let name, _)) = recorder.events.first else {
            Issue.record("expected reminders detail, got \(String(describing: recorder.events.first))")
            return
        }
        #expect(listId == "ek-list")
        #expect(name == "Groceries")
    }
}

@Suite("TasksViewModel · Done & Lists")
@MainActor
struct TasksDoneAndListsTests {

    @Test("Done groups per calendar day, newest first, with dated labels")
    func doneGroups() async {
        let today = makeTask(id: "a", completed: true, completedAt: .now)
        let yesterday = makeTask(id: "b", completed: true, completedAt: daysFromNow(-1).addingTimeInterval(3600))
        let lastWeek = makeTask(id: "c", completed: true, completedAt: daysFromNow(-6))
        let (vm, _, _) = makeTasksVM(completed: [today, yesterday, lastWeek])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.done))

        let groups = vm.uiState.groups
        #expect(groups.count == 3)
        #expect(groups[0].label == "Today")
        #expect(groups[1].label == "Yesterday")
        let expectedDayLabel = daysFromNow(-6).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        #expect(groups[2].label == expectedDayLabel, "older days read their date, not a lumped 'Earlier'")
        #expect(groups.map { $0.items.map(\.id) } == [["a"], ["b"], ["c"]])
        #expect(vm.uiState.subtitle == "3 done this week")
        #expect(groups[0].items[0].state == .done)
        #expect(groups[0].items[0].chip == "Done")
    }

    @Test("the celebration counts only today's completions - honest coins")
    func celebrationHonestCopy() async {
        let today1 = makeTask(id: "a", completed: true, completedAt: .now)
        let today2 = makeTask(id: "b", completed: true, completedAt: .now)
        let yesterday = makeTask(id: "c", completed: true, completedAt: daysFromNow(-1).addingTimeInterval(3600))
        let (vm, _, _) = makeTasksVM(completed: [today1, today2, yesterday])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.done))
        #expect(vm.uiState.doneCelebration == "Earned +20 coins today")
    }

    @Test("no completions today → no celebration banner at all")
    func celebrationNeedsTodayCompletions() async {
        let yesterday = makeTask(completed: true, completedAt: daysFromNow(-1).addingTimeInterval(3600))
        let (vm, _, _) = makeTasksVM(completed: [yesterday])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.done))
        #expect(vm.uiState.doneCelebration == nil)
    }

    @Test("dismissing the celebration hides it for the rest of the day, across rebuilds")
    func celebrationDismissal() async {
        let done = makeTask(id: "a", completed: true, completedAt: .now)
        let defaults = makeTestDefaults()
        let (vm, _, _) = makeTasksVM(completed: [done], defaults: defaults)
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.selectSegment(.done))
        #expect(vm.uiState.doneCelebration != nil)

        await vm.triggerAsync(.dismissCelebration)
        #expect(vm.uiState.doneCelebration == nil)

        // Survives a re-derivation AND a fresh view model on the same defaults.
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.doneCelebration == nil)
        let (vm2, _, _) = makeTasksVM(completed: [done], defaults: defaults)
        await vm2.triggerAsync(.refresh)
        await vm2.triggerAsync(.selectSegment(.done))
        #expect(vm2.uiState.doneCelebration == nil)
    }

    @Test("completed-today shows as its own group at the bottom of Today")
    func completedTodayGroupOnToday() async {
        let open = makeTask(id: "t1", dueAt: startOfToday)
        let done = makeTask(id: "d1", completed: true, completedAt: .now)
        let (vm, _, _) = makeTasksVM(incomplete: [open], completed: [done])
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.groups.map(\.label) == ["Today", "Completed today"])
        #expect(vm.uiState.groups[1].items.map(\.id) == ["d1"])
        #expect(vm.uiState.groups[1].items[0].state == .done)
    }

    @Test("the upcoming footnote explains the buckets - and only shows there")
    func upcomingFootnote() async {
        let (vm, _, _) = makeTasksVM(incomplete: [makeTask(dueAt: daysFromNow(2))])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.footnote == nil)
        await vm.triggerAsync(.selectSegment(.upcoming))
        let footnote = try! #require(vm.uiState.footnote)
        #expect(footnote.contains("Repeating tasks"))
        await vm.triggerAsync(.selectSegment(.done))
        #expect(vm.uiState.footnote == nil)
    }

    @Test("tapping a list row navigates to its detail screen")
    func listRowNavigation() async {
        let work = TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0)
        let (vm, _, _) = makeTasksVM(lists: [work])
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.refresh)

        await vm.triggerAsync(.listTapped("inbox"))
        await vm.triggerAsync(.listTapped("work"))
        await vm.triggerAsync(.listTapped("missing"))
        await recorder.drain()

        #expect(recorder.events.count == 2, "unknown ids never navigate")
        guard case .showListDetail(.inbox) = recorder.events[0] else {
            Issue.record("expected inbox detail, got \(recorder.events[0])")
            return
        }
        guard case .showListDetail(.mochi(let list)) = recorder.events[1] else {
            Issue.record("expected work detail, got \(recorder.events[1])")
            return
        }
        #expect(list.id == "work")
    }

    @Test("task rows carry their list's name and color")
    func rowListIndicator() async {
        let work = TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0)
        let inList = makeTask(id: "t1", dueAt: startOfToday, listId: "work")
        let inboxTask = makeTask(id: "t2", dueAt: startOfToday)
        let (vm, _, _) = makeTasksVM(incomplete: [inList, inboxTask], lists: [work])
        await vm.triggerAsync(.refresh)
        let items = vm.uiState.groups.flatMap(\.items)
        let listed = try! #require(items.first { $0.id == "t1" })
        #expect(listed.listName == "Work")
        #expect(listed.listColor != nil)
        let inbox = try! #require(items.first { $0.id == "t2" })
        #expect(inbox.listName == nil)
    }

    @Test("Lists counts open tasks per list, with the implicit Inbox first")
    func listCounts() async {
        let lists = [
            TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0),
            TaskList(id: "health", name: "Health", colorHex: "#9BE6B4", icon: "heart.fill", order: 1),
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
