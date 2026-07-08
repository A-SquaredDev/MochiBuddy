//
//  HomeViewModelTests.swift
//  MochiBuddyTests
//
//  Home derives everything from the domain: today's scope and ordering,
//  the mood readout, quick capture, and the treat economy.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeHomeVM(
    incomplete: [TaskItem] = [],
    completedStats: [CompletedTaskStat] = [],
    profile: UserProfile = makeProfile(coins: 100, streak: 4)
) -> (HomeViewModel, StubTaskRepository, StubProfileRepository, StubComfortBufferStore) {
    let auth = StubAuthRepository()
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = incomplete
    taskRepo.completedStats = completedStats
    let buffer = StubComfortBufferStore()
    let vm = HomeViewModel(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        bufferStore: buffer,
        rewardsStore: RewardsStore(profileRepository: profileRepo),
        completionStore: TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo)
        )
    )
    return (vm, taskRepo, profileRepo, buffer)
}

@Suite("HomeViewModel · today scope")
@MainActor
struct HomeTodayScopeTests {

    @Test("overdue first, then today's, then undated — future tasks excluded")
    func ordering() async {
        let calendar = Calendar.current
        let now = Date.now
        let overdue = makeTask(id: "overdue", dueAt: now.addingTimeInterval(-24 * 3600), hasTime: true)
        let laterToday = makeTask(id: "today", dueAt: calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now), hasTime: true)
        let undated = makeTask(id: "someday")
        let nextWeek = makeTask(id: "future", dueAt: now.addingTimeInterval(6 * 24 * 3600), hasTime: true)

        let (vm, _, _, _) = makeHomeVM(incomplete: [nextWeek, undated, laterToday, overdue])
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.todayItems.map(\.id) == ["overdue", "today", "someday"])
        #expect(vm.uiState.leftText == "3 left")
        #expect(vm.uiState.showEmptyToday == false)
    }

    @Test("the glance list caps at 4 rows but counts everything remaining")
    func capAtFour() async {
        let tasks = (0..<6).map { makeTask(id: "t\($0)", dueAt: Calendar.current.startOfDay(for: .now)) }
        let (vm, _, _, _) = makeHomeVM(incomplete: tasks)
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.todayItems.count == 4)
        #expect(vm.uiState.leftText == "6 left")
    }

    @Test("no tasks in scope shows the calm empty state")
    func emptyState() async {
        let future = makeTask(dueAt: Date.now.addingTimeInterval(3 * 24 * 3600), hasTime: true)
        let (vm, _, _, _) = makeHomeVM(incomplete: [future])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.showEmptyToday == true)
        #expect(vm.uiState.todayItems.isEmpty)
    }

    @Test("overdue rows carry danger state and their meta names the lateness")
    func overdueRow() async {
        let overdue = makeTask(id: "o", dueAt: Date.now.addingTimeInterval(-2 * 24 * 3600), hasTime: true, priority: .high)
        let (vm, _, _, _) = makeHomeVM(incomplete: [overdue])
        await vm.triggerAsync(.refresh)
        let item = vm.uiState.todayItems[0]
        #expect(item.state == .overdue)
        #expect(item.meta.contains("Overdue by 2 days"))
        #expect(item.chip == "High")
    }

    @Test("mood fields reflect the engine: one fresh overdue reads sleepy/uneasy")
    func moodReadout() async {
        let overdue = makeTask(dueAt: Date.now.addingTimeInterval(-24 * 3600), hasTime: true)
        let (vm, _, _, _) = makeHomeVM(incomplete: [overdue])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.baseline < MoodEngine.Constants.anchor)
        #expect(vm.uiState.moodTitle == "Mochi's getting sleepy" || vm.uiState.moodTitle == "Mochi feels content")
    }

    @Test("vacation mode swaps the mood copy and shields the baseline")
    func vacationCopy() async {
        let overdue = makeTask(dueAt: Date.now.addingTimeInterval(-48 * 3600), hasTime: true)
        let (vm, _, _, _) = makeHomeVM(incomplete: [overdue], profile: makeProfile(vacationMode: true))
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.moodTitle == "Mochi is resting")
        #expect(vm.uiState.baseline == MoodEngine.Constants.anchor)
    }
}

@Suite("HomeViewModel · actions")
@MainActor
struct HomeActionTests {

    @Test("quick add trims, saves a date-only task due today, and clears the field")
    func quickAdd() async {
        let (vm, taskRepo, _, _) = makeHomeVM()
        await vm.triggerAsync(.quickAddChanged("  Water the plants  "))
        await vm.triggerAsync(.quickAddSubmitted)

        let draft = try! #require(taskRepo.addedDrafts.first)
        #expect(draft.title == "Water the plants")
        #expect(draft.hasTime == false)
        #expect(draft.dueAt == Calendar.current.startOfDay(for: .now))
        #expect(vm.uiState.quickAddText.isEmpty)
        #expect(vm.uiState.todayItems.contains { $0.title == "Water the plants" })
    }

    @Test("quick add ignores whitespace-only input")
    func quickAddRejectsEmpty() async {
        let (vm, taskRepo, _, _) = makeHomeVM()
        await vm.triggerAsync(.quickAddChanged("   "))
        await vm.triggerAsync(.quickAddSubmitted)
        #expect(taskRepo.addedDrafts.isEmpty)
    }

    @Test("completing a task pays coins, bumps the streak, and keeps the row visible as done")
    func toggleComplete() async {
        let task = makeTask(id: "t1", dueAt: Calendar.current.startOfDay(for: .now))
        let (vm, taskRepo, _, _) = makeHomeVM(incomplete: [task], profile: makeProfile(coins: 0, streak: 0))
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("t1"))

        #expect(taskRepo.setCompletedCalls.first?.completed == true)
        #expect(vm.uiState.coins == RewardsStore.coinsPerTask)
        #expect(vm.uiState.streakDays == 1)
        let item = try! #require(vm.uiState.todayItems.first { $0.id == "t1" })
        #expect(item.state == .done)
        #expect(vm.uiState.leftText == "0 left")
    }

    @Test("undoing a completion claws the coins back")
    func toggleUndo() async {
        let task = makeTask(id: "t1", dueAt: Calendar.current.startOfDay(for: .now))
        let (vm, _, _, _) = makeHomeVM(incomplete: [task], profile: makeProfile(coins: 0))
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("t1"))
        let afterComplete = vm.uiState.coins
        await vm.triggerAsync(.toggleTask("t1"))
        #expect(afterComplete == RewardsStore.coinsPerTask)
        #expect(vm.uiState.coins == 0)
        #expect(vm.uiState.leftText == "1 left")
    }

    @Test("petting adds the pet boost and lifts the displayed mood, not the baseline")
    func petting() async {
        let (vm, _, _, buffer) = makeHomeVM()
        await vm.triggerAsync(.refresh)
        let baselineBefore = vm.uiState.baseline
        await vm.triggerAsync(.petTapped)

        #expect(buffer.boosts.count == 1)
        #expect(buffer.boosts.first?.lift == TreatCatalog.Pet.lift)
        #expect(vm.uiState.baseline == baselineBefore, "pets never move the baseline")
        #expect(vm.uiState.displayedMood > baselineBefore)
        #expect(vm.uiState.buffer > 0)
    }

    @Test("giving an affordable treat spends coins and boosts the buffer")
    func giveTreat() async {
        let (vm, _, profileRepo, buffer) = makeHomeVM(profile: makeProfile(coins: 100))
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.giveTreat("dango"))

        #expect(vm.uiState.coins == 70)
        #expect(profileRepo.coinDeltas.contains(-30))
        #expect(buffer.boosts.first?.lift == 18)
    }

    @Test("a treat you can't afford is a hard no-op")
    func unaffordableTreat() async {
        let (vm, _, profileRepo, buffer) = makeHomeVM(profile: makeProfile(coins: 5))
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.giveTreat("cupcake"))

        #expect(vm.uiState.coins == 5)
        #expect(profileRepo.coinDeltas.isEmpty)
        #expect(buffer.boosts.isEmpty)
    }

    @Test("treat afford flags track the balance")
    func affordFlags() async {
        let (vm, _, _, _) = makeHomeVM(profile: makeProfile(coins: 22))
        await vm.triggerAsync(.refresh)
        let byId = Dictionary(uniqueKeysWithValues: vm.uiState.treats.map { ($0.id, $0.canAfford) })
        #expect(byId["berry"] == true)    // 15
        #expect(byId["latte"] == true)    // 22
        #expect(byId["dango"] == false)   // 30
        #expect(byId["cupcake"] == false) // 55
    }

    @Test("completing a repeating task appends the spawned occurrence to the domain")
    func repeatSpawnLandsInDomain() async {
        let task = makeTask(id: "t1", dueAt: Calendar.current.startOfDay(for: .now), repeatRule: .daily)
        let (vm, taskRepo, _, _) = makeHomeVM(incomplete: [task])
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("t1"))
        #expect(taskRepo.addedDrafts.count == 1, "the next daily occurrence must be created")
        // Tomorrow's occurrence is out of today's scope — the done row remains.
        #expect(vm.uiState.todayItems.map(\.id) == ["t1"])
    }
}
