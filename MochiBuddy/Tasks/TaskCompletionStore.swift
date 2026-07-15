//
//  TaskCompletionStore.swift
//  MochiBuddy
//
//  The one place a check-off happens - Home and the Tasks tab both route
//  through here so persistence, coins/streak, and repeat-spawning never
//  drift apart. Completing a repeating occurrence spawns the next one.
//

import Foundation

@MainActor
final class TaskCompletionStore {

    struct ToggleOutcome {
        let coinsDelta: Int
        /// Updated streak - only present when a completion extended it.
        let streak: Int?
        /// The next occurrence created for a repeating task.
        let spawnedNext: TaskItem?
        /// The spawned occurrence deleted because its completion was undone
        /// - callers must drop it from their local arrays too.
        var reapedTaskId: String? = nil
    }

    private let taskRepository: TaskRepository
    private let rewardsStore: RewardsStore

    /// Which spawn each completion created, so an undo can reap it instead
    /// of leaving a duplicate future occurrence behind. Session-scoped: an
    /// undo after relaunch can't reap (the link isn't persisted), which
    /// matches the old behavior at worst.
    private var spawnByCompletedTaskId: [String: String] = [:]

    init(taskRepository: TaskRepository, rewardsStore: RewardsStore) {
        self.taskRepository = taskRepository
        self.rewardsStore = rewardsStore
    }

    func setCompleted(
        _ task: TaskItem,
        completed: Bool,
        currentCoins: Int,
        userId: String
    ) async -> ToggleOutcome {
        try? await taskRepository.setCompleted(taskId: task.id, completed: completed, userId: userId)

        guard completed else {
            let delta = await rewardsStore.revokeCompletion(currentCoins: currentCoins, userId: userId)
            var reaped: String?
            if let spawnedId = spawnByCompletedTaskId.removeValue(forKey: task.id) {
                try? await taskRepository.deleteTask(id: spawnedId, userId: userId)
                reaped = spawnedId
            }
            return ToggleOutcome(coinsDelta: delta, streak: nil, spawnedNext: nil, reapedTaskId: reaped)
        }

        var spawned: TaskItem?
        if let rule = task.repeatRule, let due = task.dueAt {
            let nextDue = rule.nextOccurrence(after: due)
            let draft = TaskDraft(
                title: task.title,
                notes: task.notes,
                dueAt: nextDue,
                hasTime: task.hasTime,
                priority: task.priority,
                listId: task.listId,
                repeatRule: rule
            )
            if let id = try? await taskRepository.addTask(draft, userId: userId) {
                spawned = TaskItem(
                    id: id, title: task.title, notes: task.notes,
                    dueAt: nextDue, hasTime: task.hasTime, priority: task.priority,
                    listId: task.listId, repeatRule: rule,
                    completed: false, completedAt: nil, createdAt: .now
                )
                spawnByCompletedTaskId[task.id] = id
            }
        }

        let outcome = await rewardsStore.awardCompletion(userId: userId)
        return ToggleOutcome(coinsDelta: outcome.coinsDelta, streak: outcome.streak, spawnedNext: spawned)
    }
}
