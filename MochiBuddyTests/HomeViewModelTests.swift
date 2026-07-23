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
    completed: [TaskItem] = [],
    completedStats: [CompletedTaskStat] = [],
    lists: [TaskList] = [],
    profile: UserProfile = makeProfile(coins: 100, streak: 4),
    membership explicitMembership: MembershipSession? = nil,
    reentry explicitReentry: VacationReentryService? = nil,
    celebrationCenter: CelebrationCenter? = nil
) -> (HomeViewModel, StubTaskRepository, StubProfileRepository, StubComfortBufferStore) {
    let membership = explicitMembership ?? MembershipSession()
    let auth = StubAuthRepository()
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = incomplete
    taskRepo.completed = completed
    taskRepo.completedStats = completedStats
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let buffer = StubComfortBufferStore()
    let vm = HomeViewModel(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        listRepository: listRepo,
        bufferStore: buffer,
        rewardsStore: RewardsStore(profileRepository: profileRepo),
        completionStore: TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: membership
        ),
        membershipSession: membership,
        recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
        relay: StubRelay(),
        reentryService: explicitReentry ?? VacationReentryService(
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            bufferStore: buffer,
            relay: StubRelay(),
            defaults: UserDefaults(suiteName: "reentry-\(UUID())")!
        ),
        celebrationCenter: celebrationCenter ?? CelebrationCenter()
    )
    return (vm, taskRepo, profileRepo, buffer)
}

@Suite("HomeViewModel · loading")
@MainActor
struct HomeLoadingTests {

    @Test("skeleton shows until the first refresh lands, then never again")
    func loadingClearsAfterRefresh() async {
        let (vm, _, _, _) = makeHomeVM(incomplete: [makeTask(id: "t1")])
        #expect(vm.uiState.isLoading == true)
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.isLoading == false)
    }

    @Test("loading clears even when signed out, so the skeleton never sticks")
    func loadingClearsWithoutUser() async {
        let auth = StubAuthRepository()
        auth.currentAccount = nil
        let profileRepo = StubProfileRepository()
        let taskRepo = StubTaskRepository()
        let vm = HomeViewModel(
            authRepository: auth,
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            listRepository: StubListRepository(),
            bufferStore: StubComfortBufferStore(),
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            completionStore: TaskCompletionStore(
                taskRepository: taskRepo,
                rewardsStore: RewardsStore(profileRepository: profileRepo),
                membershipSession: MembershipSession()
            ),
            membershipSession: MembershipSession(),
            recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
            relay: StubRelay(),
            reentryService: VacationReentryService(
                profileRepository: profileRepo,
                taskRepository: taskRepo,
                bufferStore: StubComfortBufferStore(),
                relay: StubRelay(),
                defaults: UserDefaults(suiteName: "reentry-\(UUID())")!
            ),
            celebrationCenter: CelebrationCenter()
        )
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.isLoading == false)
    }
}

@Suite("HomeViewModel · celebrations")
@MainActor
struct HomeCelebrationTests {

    @Test("a landed milestone celebrates on Home once, then dismisses cleanly")
    func milestoneCelebration() async {
        let center = CelebrationCenter()
        let (vm, _, _, _) = makeHomeVM(celebrationCenter: center)
        center.post(milestone: 7)

        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.celebrationText == StreakMilestones.celebrationText(days: 7))
        #expect(center.pendingMilestone == nil, "consumed once shown")

        await vm.triggerAsync(.dismissCelebration)
        #expect(vm.uiState.celebrationText == nil)
        await vm.triggerAsync(.tick)
        #expect(vm.uiState.celebrationText == nil, "a dismissed banner stays dismissed")
    }

    @Test("the center keeps only the deepest pending milestone - a drained widget queue coalesces")
    func centerCoalesces() {
        let center = CelebrationCenter()
        center.post(milestone: 7)
        center.post(milestone: 30)
        center.post(milestone: 7)
        #expect(center.consumeMilestone() == 30)
        #expect(center.consumeMilestone() == nil)
    }
}

@Suite("HomeViewModel · today scope")
@MainActor
struct HomeTodayScopeTests {

    @Test("overdue first, then today's, then undated - future tasks excluded")
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

    @Test("every scoped task is listed - the count and the rows always agree")
    func noCap() async {
        let tasks = (0..<6).map { makeTask(id: "t\($0)", dueAt: Calendar.current.startOfDay(for: .now)) }
        let (vm, _, _, _) = makeHomeVM(incomplete: tasks)
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.todayItems.count == 6)
        #expect(vm.uiState.leftText == "6 left")
    }

    @Test("tasks completed today land in their own Done section, not Today")
    func doneTodaySection() async {
        let doneAtNoon = makeTask(
            id: "d1", completed: true,
            completedAt: Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        )
        let open = makeTask(id: "t1", dueAt: Calendar.current.startOfDay(for: .now))
        let (vm, _, _, _) = makeHomeVM(incomplete: [open], completed: [doneAtNoon])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.todayItems.map(\.id) == ["t1"])
        #expect(vm.uiState.doneTodayItems.map(\.id) == ["d1"])
        #expect(vm.uiState.doneTodayItems[0].state == .done)
        #expect(vm.uiState.leftText == "1 left")
    }

    @Test("the week preview groups days 1–6 out and skips further-out tasks")
    func weekPreview() async {
        let tomorrow = makeTask(id: "a", title: "Gym", dueAt: Date.now.addingTimeInterval(1 * 24 * 3600))
        let plus3 = makeTask(id: "b", title: "Groceries", dueAt: Date.now.addingTimeInterval(3 * 24 * 3600))
        let plus9 = makeTask(id: "c", dueAt: Date.now.addingTimeInterval(9 * 24 * 3600))
        let (vm, _, _, _) = makeHomeVM(incomplete: [plus9, plus3, tomorrow])
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.weekPreview.map(\.id) == ["d1", "d3"])
        #expect(vm.uiState.weekPreview[0].dayLabel == "Tomorrow")
        #expect(vm.uiState.weekPreview[0].summary == "Gym")
        #expect(vm.uiState.weekPreview[1].count == 1)
    }

    @Test("rows carry their list's name and color; inbox rows carry none")
    func listIndicator() async {
        let groceries = TaskList(id: "l1", name: "Groceries", colorHex: "#8FD3F4", icon: "cart.fill", order: 0)
        let inList = makeTask(id: "t1", dueAt: Calendar.current.startOfDay(for: .now), listId: "l1")
        let inboxTask = makeTask(id: "t2", dueAt: Calendar.current.startOfDay(for: .now))
        let (vm, _, _, _) = makeHomeVM(incomplete: [inList, inboxTask], lists: [groceries])
        await vm.triggerAsync(.refresh)
        let listed = try! #require(vm.uiState.todayItems.first { $0.id == "t1" })
        #expect(listed.listName == "Groceries")
        #expect(listed.listColor != nil)
        let inbox = try! #require(vm.uiState.todayItems.first { $0.id == "t2" })
        #expect(inbox.listName == nil)
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
        #expect(vm.uiState.moodTitle == "Mochi is getting sleepy" || vm.uiState.moodTitle == "Mochi feels content")
    }

    @Test("vacation mode swaps the mood copy and shields the baseline")
    func vacationCopy() async {
        let overdue = makeTask(dueAt: Date.now.addingTimeInterval(-48 * 3600), hasTime: true)
        let (vm, _, _, _) = makeHomeVM(incomplete: [overdue], profile: makeProfile(vacationMode: true))
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.moodTitle == "Mochi is resting")
        #expect(vm.uiState.baseline == MoodEngine.Constants.anchor)
    }

    @Test("inside the bedtime window Mochi sleeps")
    func bedtimeSleeps() async {
        // A window covering the whole day so the test passes at any hour.
        let allDay = BedtimeWindow(startMinutes: 0, endMinutes: 24 * 60)
        let (vm, _, _, _) = makeHomeVM(profile: makeProfile(bedtime: allDay))
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.isSleeping == true)
        #expect(vm.uiState.moodTitle == "Mochi is sleeping")
    }

    @Test("vacation pins the resting pose and its copy outranks bedtime")
    func vacationOutranksBedtime() async {
        let allDay = BedtimeWindow(startMinutes: 0, endMinutes: 24 * 60)
        let (vm, _, _, _) = makeHomeVM(profile: makeProfile(vacationMode: true, bedtime: allDay))
        await vm.triggerAsync(.refresh)
        // v0.5: the resting pose is pinned for the whole trip (rendered
        // with the sleeping pose until the holiday art lands).
        #expect(vm.uiState.isSleeping == true)
        #expect(vm.uiState.moodTitle == "Mochi is resting")
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

    @Test("a post-submit echo of the submitted title can't resurrect the cleared field")
    func quickAddSwallowsEcho() async {
        let (vm, _, _, _) = makeHomeVM()
        await vm.triggerAsync(.quickAddChanged("Buuy milk"))
        await vm.triggerAsync(.quickAddSubmitted)
        // A focused TextField can push its buffer back repeatedly (autocorrect
        // commit, focus resign, sheet presentation) - every echo of the exact
        // submitted title must be ignored…
        await vm.triggerAsync(.quickAddChanged("Buuy milk"))
        await vm.triggerAsync(.quickAddChanged("Buuy milk"))
        #expect(vm.uiState.quickAddText.isEmpty)
        // …while genuinely new input still lands.
        await vm.triggerAsync(.quickAddChanged("Call mom"))
        #expect(vm.uiState.quickAddText == "Call mom")
    }

    @Test("quick add ignores whitespace-only input")
    func quickAddRejectsEmpty() async {
        let (vm, taskRepo, _, _) = makeHomeVM()
        await vm.triggerAsync(.quickAddChanged("   "))
        await vm.triggerAsync(.quickAddSubmitted)
        #expect(taskRepo.addedDrafts.isEmpty)
    }

    @Test("the plus button opens the editor seeded with the typed title and clears the field")
    func composeWithDraft() async {
        let (vm, taskRepo, _, _) = makeHomeVM()
        await vm.triggerAsync(.quickAddChanged("  Plan the trip  "))
        await vm.triggerAsync(.composeTapped)

        let editing = try! #require(vm.uiState.editingTask)
        #expect(editing.task == nil)
        #expect(editing.draftTitle == "Plan the trip")
        #expect(vm.uiState.quickAddText.isEmpty)
        #expect(taskRepo.addedDrafts.isEmpty, "compose opens the editor - it never instant-adds")
        // The echo guard covers this path too.
        await vm.triggerAsync(.quickAddChanged("  Plan the trip  "))
        #expect(vm.uiState.quickAddText.isEmpty)
    }

    @Test("the plus button with an empty field opens a blank editor")
    func composeBlank() async {
        let (vm, _, _, _) = makeHomeVM()
        await vm.triggerAsync(.composeTapped)
        let editing = try! #require(vm.uiState.editingTask)
        #expect(editing.task == nil)
        #expect(editing.draftTitle == nil)
    }

    @Test("an active boost surfaces a fade countdown that clears when the boost dies")
    func boostCountdown() async {
        let (vm, _, _, buffer) = makeHomeVM()
        await vm.triggerAsync(.refresh)
        #expect(vm.uiState.boostFadeText == nil)

        await vm.triggerAsync(.petTapped)
        let text = try! #require(vm.uiState.boostFadeText)
        #expect(text.hasPrefix("boost fades in ~"))

        buffer.value = 0
        await vm.triggerAsync(.tick)
        #expect(vm.uiState.boostFadeText == nil)
    }

    @Test("completing a task pays coins, bumps the streak, and moves the row to Done today")
    func toggleComplete() async {
        let task = makeTask(id: "t1", dueAt: Calendar.current.startOfDay(for: .now))
        let (vm, taskRepo, _, _) = makeHomeVM(incomplete: [task], profile: makeProfile(coins: 0, streak: 0))
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.toggleTask("t1"))

        #expect(taskRepo.setCompletedCalls.first?.completed == true)
        #expect(vm.uiState.coins == RewardsStore.coinsPerTask)
        #expect(vm.uiState.streakDays == 1)
        #expect(vm.uiState.todayItems.isEmpty)
        let item = try! #require(vm.uiState.doneTodayItems.first { $0.id == "t1" })
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
        #expect(vm.uiState.doneTodayItems.isEmpty, "undo moves the row back to Today")
        #expect(vm.uiState.todayItems.map(\.id) == ["t1"])
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
        // Tomorrow's occurrence is out of today's scope; the done row moved
        // to the Done-today section and the spawn shows in the week preview.
        #expect(vm.uiState.todayItems.isEmpty)
        #expect(vm.uiState.doneTodayItems.map(\.id) == ["t1"])
        #expect(vm.uiState.weekPreview.map(\.id) == ["d1"])
    }
}
