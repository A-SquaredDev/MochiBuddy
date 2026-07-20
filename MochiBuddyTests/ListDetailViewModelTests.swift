//
//  ListDetailViewModelTests.swift
//  MochiBuddyTests
//
//  One list's tasks: scoping by listId (inbox = nil), the open/done split,
//  and check-offs routing through TaskCompletionStore.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeListDetailVM(
    source: ListDetailSource,
    incomplete: [TaskItem] = [],
    completed: [TaskItem] = [],
    profile: UserProfile = makeProfile(coins: 50),
    reminders: StubRemindersGateway = StubRemindersGateway()
) -> (ListDetailViewModel, StubTaskRepository, StubProfileRepository) {
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = incomplete
    taskRepo.completed = completed
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    let vm = ListDetailViewModel(
        source: source,
        authRepository: StubAuthRepository(),
        taskRepository: taskRepo,
        profileRepository: profileRepo,
        completionStore: TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: MembershipSession()
        ),
        remindersGateway: reminders,
        membershipSession: MembershipSession(),
        recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
        relay: StubRelay()
    )
    return (vm, taskRepo, profileRepo)
}

private let workList = TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0)

@Suite("ListDetail · scoping")
@MainActor
struct ListDetailScopingTests {

    @Test("a list shows only its own tasks, split into open and done")
    func scopesToList() async {
        let inWork = makeTask(id: "w1", listId: "work")
        let inOther = makeTask(id: "o1", listId: "health")
        let inInbox = makeTask(id: "i1")
        let doneInWork = makeTask(id: "w2", listId: "work", completed: true, completedAt: .now)
        let (vm, _, _) = makeListDetailVM(
            source: .mochi(workList),
            incomplete: [inWork, inOther, inInbox],
            completed: [doneInWork]
        )
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.title == "Work")
        #expect(vm.uiState.openItems.map(\.id) == ["w1"])
        #expect(vm.uiState.doneItems.map(\.id) == ["w2"])
        #expect(vm.uiState.subtitle == "1 open · 1 done")
        #expect(vm.uiState.newTaskListId == "work")
        #expect(vm.uiState.showEmpty == false)
    }

    @Test("the Inbox shows only listId-less tasks")
    func inboxScope() async {
        let inInbox = makeTask(id: "i1")
        let inWork = makeTask(id: "w1", listId: "work")
        let (vm, _, _) = makeListDetailVM(source: .inbox, incomplete: [inInbox, inWork])
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.title == "Inbox")
        #expect(vm.uiState.openItems.map(\.id) == ["i1"])
        #expect(vm.uiState.newTaskListId == nil)
    }

    @Test("an empty list shows the empty card")
    func emptyState() async {
        let (vm, _, _) = makeListDetailVM(source: .mochi(workList))
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.showEmpty == true)
        #expect(vm.uiState.subtitle == "0 open · 0 done")
    }
}

@Suite("ListDetail · Apple Reminders source")
@MainActor
struct ListDetailRemindersTests {

    private func makeRemindersSetup() -> (ListDetailViewModel, StubRemindersGateway) {
        let gateway = StubRemindersGateway()
        gateway.openReminders = [
            makeReminder(id: "r1", title: "Buy oat milk", listId: "ek-list"),
            makeReminder(id: "r2", title: "Other list", listId: "elsewhere"),
        ]
        let (vm, _, _) = makeListDetailVM(
            source: .reminders(listId: "ek-list", name: "Groceries", colorHex: "#8FD3F4"),
            reminders: gateway
        )
        return (vm, gateway)
    }

    @Test("shows only that list's open reminders, read-only, no add button")
    func remindersScope() async {
        let (vm, _) = makeRemindersSetup()
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.title == "Groceries")
        #expect(vm.uiState.canAdd == false)
        #expect(vm.uiState.openItems.map(\.id) == ["r1"])
        #expect(vm.uiState.openItems[0].sourceBadge == "Reminders")
        #expect(vm.uiState.subtitle.contains("stay in Apple Reminders"))

        // No editor for reminder rows.
        await vm.triggerAsync(.taskTapped("r1"))
        #expect(vm.uiState.editingTask == nil)
    }

    @Test("check-offs write back through the gateway and revert on failure")
    func remindersToggle() async {
        let (vm, gateway) = makeRemindersSetup()
        await vm.triggerAsync(.refresh)

        await vm.triggerAsync(.toggleTask("r1"))
        #expect(gateway.setCompletedCalls.map(\.id) == ["r1"])
        #expect(vm.uiState.openItems.isEmpty)
        #expect(vm.uiState.doneItems.map(\.id) == ["r1"])

        gateway.setCompletedResult = false
        await vm.triggerAsync(.toggleTask("r1"))
        #expect(vm.uiState.doneItems.map(\.id) == ["r1"], "failed save reverts the un-complete")
    }
}

@Suite("ListDetail · toggling")
@MainActor
struct ListDetailToggleTests {

    @Test("checking off moves the row to done and persists through the completion store")
    func toggleRoundTrip() async {
        let task = makeTask(id: "w1", dueAt: Calendar.current.startOfDay(for: .now), listId: "work")
        let (vm, taskRepo, profileRepo) = makeListDetailVM(
            source: .mochi(workList), incomplete: [task], profile: makeProfile(coins: 0)
        )
        await vm.triggerAsync(.refresh)

        await vm.triggerAsync(.toggleTask("w1"))
        #expect(vm.uiState.openItems.isEmpty)
        #expect(vm.uiState.doneItems.map(\.id) == ["w1"])
        #expect(taskRepo.setCompletedCalls.first?.completed == true)
        #expect(profileRepo.coinDeltas == [RewardsStore.coinsPerTask])

        await vm.triggerAsync(.toggleTask("w1"))
        #expect(vm.uiState.openItems.map(\.id) == ["w1"])
        #expect(vm.uiState.doneItems.isEmpty)
    }

    @Test("completing a repeating task keeps the spawned occurrence in this list")
    func repeatSpawnStaysInList() async {
        let task = makeTask(
            id: "w1",
            dueAt: Calendar.current.startOfDay(for: .now),
            listId: "work", repeatRule: .daily
        )
        let (vm, taskRepo, _) = makeListDetailVM(source: .mochi(workList), incomplete: [task])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("w1"))

        #expect(taskRepo.addedDrafts.count == 1)
        // The spawned occurrence is due tomorrow but still belongs here.
        #expect(vm.uiState.openItems.count == 1)
        #expect(vm.uiState.doneItems.map(\.id) == ["w1"])
    }
}
