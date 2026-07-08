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

    private func makeStore() -> (TaskCompletionStore, StubTaskRepository, StubProfileRepository) {
        let taskRepo = StubTaskRepository()
        let profileRepo = StubProfileRepository()
        let store = TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo)
        )
        return (store, taskRepo, profileRepo)
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

    @Test("un-completing with a low balance clamps the clawback")
    func uncompleteClamps() async {
        let (store, _, _) = makeStore()
        let task = makeTask(completed: true)
        let outcome = await store.setCompleted(task, completed: false, currentCoins: 3, userId: "user1")
        #expect(outcome.coinsDelta == -3)
    }
}
