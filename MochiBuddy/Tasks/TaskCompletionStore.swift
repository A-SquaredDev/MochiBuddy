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
        /// Set when this completion landed a sparse streak milestone
        /// (7 / 30 / every 50) - the celebration hook.
        var milestoneStreak: Int? = nil
    }

    private let taskRepository: TaskRepository
    private let rewardsStore: RewardsStore
    private let membershipSession: MembershipSession

    /// Fired after every persisted toggle - the notification re-lay hook.
    var onMutation: (() -> Void)?

    /// Fired when a completion lands a sparse streak milestone - the
    /// celebration hook, one level above whichever surface checked off.
    var onMilestone: ((Int) -> Void)?

    /// Which spawn each completion created, so an undo can reap it instead
    /// of leaving a duplicate future occurrence behind. Session-scoped: an
    /// undo after relaunch can't reap (the link isn't persisted), which
    /// matches the old behavior at worst.
    private var spawnByCompletedTaskId: [String: String] = [:]

    /// Tasks already completed this session, so a stale row (the drain or
    /// another surface finished it while a list still showed it open) taps
    /// through to a no-op instead of a second award, a second spawned
    /// occurrence, and a completedAt overwrite. Session-scoped like the
    /// spawn map; a fresh session loads fresh rows.
    private var completedTaskIds: Set<String> = []

    init(
        taskRepository: TaskRepository,
        rewardsStore: RewardsStore,
        membershipSession: MembershipSession
    ) {
        self.taskRepository = taskRepository
        self.rewardsStore = rewardsStore
        self.membershipSession = membershipSession
    }

    /// `localContext` and `completedAt` carry completion-time stamps for
    /// completions that happened earlier than this call (the widget drain);
    /// live check-offs leave both nil and the repository stamps "now".
    func setCompleted(
        _ task: TaskItem,
        completed: Bool,
        currentCoins: Int,
        userId: String,
        localContext: CompletionLocalContext? = nil,
        completedAt: Date? = nil
    ) async -> ToggleOutcome {
        if completed {
            guard completedTaskIds.insert(task.id).inserted else {
                return ToggleOutcome(coinsDelta: 0, streak: nil, spawnedNext: nil)
            }
        } else {
            // An undo re-arms the task: complete → undo → complete is a
            // legitimate re-award (the undo clawed the coins back).
            completedTaskIds.remove(task.id)
        }
        try? await taskRepository.setCompleted(
            taskId: task.id, completed: completed, localContext: localContext,
            completedAt: completedAt, userId: userId
        )
        defer { onMutation?() }

        // Lapsed: completing stays allowed ("finish what you started") but
        // the coin balance is frozen, the streak is frozen, and recurrence
        // never spawns - the list genuinely drains instead of replenishing
        // into a free habit-tracker.
        guard !membershipSession.isLapsed else {
            return ToggleOutcome(coinsDelta: 0, streak: nil, spawnedNext: nil)
        }

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
            // Every occurrence of one habit shares one series identity -
            // the first occurrence's id, inherited down the spawn chain.
            let seriesId = task.seriesId ?? task.id
            let draft = TaskDraft(
                title: task.title,
                notes: task.notes,
                dueAt: nextDue,
                hasTime: task.hasTime,
                priority: task.priority,
                listId: task.listId,
                repeatRule: rule,
                seriesId: seriesId,
                estimatedMinutes: task.estimatedMinutes
            )
            if let id = try? await taskRepository.addTask(draft, userId: userId) {
                spawned = TaskItem(
                    id: id, title: task.title, notes: task.notes,
                    dueAt: nextDue, hasTime: task.hasTime, priority: task.priority,
                    listId: task.listId, repeatRule: rule,
                    completed: false, completedAt: nil, createdAt: .now,
                    seriesId: seriesId,
                    estimatedMinutes: task.estimatedMinutes
                )
                spawnByCompletedTaskId[task.id] = id
            }
        }

        let outcome = await rewardsStore.awardCompletion(userId: userId, completedAt: completedAt ?? .now)
        // Only the completion that actually REACHES the milestone
        // celebrates - later check-offs the same day stay quiet.
        let milestone = outcome.streakExtended && StreakMilestones.isMilestone(outcome.streak)
            ? outcome.streak : nil
        if let milestone {
            onMilestone?(milestone)
        }
        return ToggleOutcome(
            coinsDelta: outcome.coinsDelta,
            streak: outcome.streak,
            spawnedNext: spawned,
            milestoneStreak: milestone
        )
    }
}
