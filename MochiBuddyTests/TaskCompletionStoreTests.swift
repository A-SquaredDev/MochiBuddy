//
//  TaskCompletionStoreTests.swift
//  MochiBuddyTests
//
//  The single check-off path shared by Home and the Tasks tab: persist,
//  reward, and spawn the next occurrence of repeating tasks.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("TaskCompletionStore")
struct TaskCompletionStoreTests {

    private func makeStore(
        membership: MembershipSession? = nil
    ) -> (TaskCompletionStore, StubTaskRepository, StubProfileRepository) {
        let taskRepo = StubTaskRepository()
        let profileRepo = StubProfileRepository()
        let store = TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: membership ?? MembershipSession()
        )
        return (store, taskRepo, profileRepo)
    }

    private func makeLapsedSession() -> MembershipSession {
        let session = MembershipSession()
        session.status = .lapsed
        return session
    }

    @Test("lapsed: completing persists but pays nothing and spawns nothing - the list drains")
    func lapsedCompletionIsFrozen() async {
        let (store, taskRepo, profileRepo) = makeStore(membership: makeLapsedSession())
        let task = makeTask(id: "t1", dueAt: Dates.hours(-1), hasTime: true, repeatRule: .daily)
        let outcome = await store.setCompleted(task, completed: true, currentCoins: 40, userId: "user1")

        #expect(taskRepo.setCompletedCalls.first?.completed == true, "completing must still persist")
        #expect(outcome.coinsDelta == 0)
        #expect(outcome.streak == nil, "streak freezes, it never moves during lapse")
        #expect(outcome.spawnedNext == nil, "recurrence must not spawn during lapse")
        #expect(taskRepo.addedDrafts.isEmpty)
        #expect(profileRepo.coinDeltas.isEmpty)
        #expect(profileRepo.savedStreaks.isEmpty)
    }

    @Test("lapsed: undoing a completion claws nothing back - the balance stays frozen")
    func lapsedUndoIsFrozen() async {
        let (store, taskRepo, profileRepo) = makeStore(membership: makeLapsedSession())
        let task = makeTask(id: "t1", completed: true, completedAt: Dates.now)
        let outcome = await store.setCompleted(task, completed: false, currentCoins: 40, userId: "user1")

        #expect(taskRepo.setCompletedCalls.first?.completed == false)
        #expect(outcome.coinsDelta == 0)
        #expect(profileRepo.coinDeltas.isEmpty)
    }

    @Test("a completion that lands a sparse milestone fires the celebration hook; ordinary days stay quiet")
    func milestoneFiresCelebrationHook() async {
        let (store, _, profileRepo) = makeStore()
        profileRepo.profile = makeProfile(
            streak: 6,
            lastActiveDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        var milestones: [Int] = []
        store.onMilestone = { milestones.append($0) }

        let outcome = await store.setCompleted(
            makeTask(id: "t1"), completed: true, currentCoins: 0, userId: "user1"
        )
        #expect(outcome.milestoneStreak == 7, "day 6 + today = the first sparse milestone")
        #expect(milestones == [7])

        // The next completion the same day holds the streak - no re-fire,
        // so a dismissed banner never resurrects during the milestone day.
        profileRepo.profile = makeProfile(streak: 7, lastActiveDate: .now)
        let again = await store.setCompleted(
            makeTask(id: "t2"), completed: true, currentCoins: 0, userId: "user1"
        )
        #expect(again.milestoneStreak == nil)
        #expect(milestones == [7])
    }

    @Test("completing persists and pays out")
    func completePersistsAndPays() async {
        let (store, taskRepo, _) = makeStore()
        let task = makeTask(id: "t1")
        let outcome = await store.setCompleted(task, completed: true, currentCoins: 0, userId: "user1")

        #expect(taskRepo.setCompletedCalls.count == 1)
        #expect(taskRepo.setCompletedCalls.first?.taskId == "t1")
        #expect(taskRepo.setCompletedCalls.first?.completed == true)
        #expect(outcome.coinsDelta == RewardsStore.coinsPerTask)
        #expect(outcome.streak == 1)
    }

    @Test("a non-repeating task spawns nothing")
    func noSpawnWithoutRule() async {
        let (store, taskRepo, _) = makeStore()
        let task = makeTask(dueAt: Dates.now, hasTime: true)
        let outcome = await store.setCompleted(task, completed: true, currentCoins: 0, userId: "user1")
        #expect(outcome.spawnedNext == nil)
        #expect(taskRepo.addedDrafts.isEmpty)
    }

    @Test("completing a repeating task spawns the next occurrence with every field carried over")
    func spawnCarriesFields() async {
        let (store, taskRepo, _) = makeStore()
        let task = makeTask(
            title: "Physio stretches",
            notes: "The full routine",
            dueAt: Dates.hours(-1),
            hasTime: true,
            priority: .high,
            listId: "health",
            repeatRule: .daily
        )
        let outcome = await store.setCompleted(task, completed: true, currentCoins: 0, userId: "user1")

        let draft = try! #require(taskRepo.addedDrafts.first)
        #expect(draft.title == "Physio stretches")
        #expect(draft.notes == "The full routine")
        #expect(draft.priority == .high)
        #expect(draft.listId == "health")
        #expect(draft.repeatRule == .daily)
        #expect(draft.hasTime == true)
        #expect(draft.dueAt != nil && draft.dueAt! > .now, "the next occurrence must be in the future")

        let spawned = try! #require(outcome.spawnedNext)
        #expect(spawned.id == taskRepo.nextAddedTaskId)
        #expect(spawned.completed == false)
        #expect(spawned.dueAt == draft.dueAt)
    }

    @Test("a repeating task with no due date can't spawn (nothing to step from)")
    func repeatWithoutDueDate() async {
        let (store, taskRepo, _) = makeStore()
        let task = makeTask(repeatRule: .weekly)
        let outcome = await store.setCompleted(task, completed: true, currentCoins: 0, userId: "user1")
        #expect(outcome.spawnedNext == nil)
        #expect(taskRepo.addedDrafts.isEmpty)
    }

    @Test("un-completing revokes coins, touches no streak, spawns nothing")
    func uncompleteRevokes() async {
        let (store, taskRepo, _) = makeStore()
        let task = makeTask(id: "t1", dueAt: Dates.now, repeatRule: .daily, completed: true, completedAt: Dates.now)
        let outcome = await store.setCompleted(task, completed: false, currentCoins: 25, userId: "user1")

        #expect(taskRepo.setCompletedCalls.first?.completed == false)
        #expect(outcome.coinsDelta == -RewardsStore.coinsPerTask)
        #expect(outcome.streak == nil)
        #expect(outcome.spawnedNext == nil)
        #expect(taskRepo.addedDrafts.isEmpty, "undo must never spawn an occurrence")
    }

    @Test("undoing a completion reaps the occurrence it spawned")
    func undoReapsSpawn() async {
        let (store, taskRepo, _) = makeStore()
        let task = makeTask(id: "t1", dueAt: Dates.days(3), repeatRule: .weekly)

        let completed = await store.setCompleted(task, completed: true, currentCoins: 0, userId: "user1")
        let spawnedId = try! #require(completed.spawnedNext?.id)

        let undone = await store.setCompleted(task, completed: false, currentCoins: 10, userId: "user1")
        #expect(undone.reapedTaskId == spawnedId)
        #expect(taskRepo.deletedIds == [spawnedId], "the premature next occurrence must be deleted")

        // A second undo has nothing left to reap.
        let again = await store.setCompleted(task, completed: false, currentCoins: 0, userId: "user1")
        #expect(again.reapedTaskId == nil)
        #expect(taskRepo.deletedIds.count == 1)
    }

    @Test("un-completing with a low balance clamps the clawback")
    func uncompleteClamps() async {
        let (store, _, _) = makeStore()
        let task = makeTask(completed: true)
        let outcome = await store.setCompleted(task, completed: false, currentCoins: 3, userId: "user1")
        #expect(outcome.coinsDelta == -3)
    }
}

@Suite("TaskCompletionStore · effort inheritance")
struct TaskCompletionStoreEffortTests {

    @Test("a spawned occurrence inherits the effort the way it inherits seriesId")
    func spawnInheritsEffort() async {
        let taskRepo = StubTaskRepository()
        let profileRepo = StubProfileRepository()
        profileRepo.profile = makeProfile()
        let store = TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: MembershipSession()
        )
        let task = makeTask(
            id: "r1", dueAt: Dates.startOfToday, repeatRule: .daily, estimatedMinutes: 60
        )
        let outcome = await store.setCompleted(task, completed: true, currentCoins: 0, userId: "user1")
        #expect(taskRepo.addedDrafts.first?.estimatedMinutes == 60)
        #expect(outcome.spawnedNext?.estimatedMinutes == 60)
    }
}
