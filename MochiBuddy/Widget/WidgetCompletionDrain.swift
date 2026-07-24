//
//  WidgetCompletionDrain.swift
//  MochiBuddy
//
//  A Complete tapped on the widget queues in the App Group (the widget
//  intent process is too small to carry Firestore); the app makes it
//  durable here on next open, through the same completion store as every
//  other check-off - coins, streak, and recurrence spawning included.
//

import Foundation

@MainActor
final class WidgetCompletionDrain {

    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository
    private let profileRepository: UserProfileRepository
    private let completionStore: TaskCompletionStore
    private let defaults: UserDefaults

    init(
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        profileRepository: UserProfileRepository,
        completionStore: TaskCompletionStore,
        defaults: UserDefaults = MochiAppGroup.defaults
    ) {
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.profileRepository = profileRepository
        self.completionStore = completionStore
        self.defaults = defaults
    }

    /// Persist every queued widget completion. Ids whose tasks are gone
    /// or already done drop silently. Returns how many landed.
    @discardableResult
    func drain() async -> Int {
        let queue = WidgetStateStore.drainCompletions(defaults: defaults)
        guard !queue.isEmpty, let userId = authRepository.currentAccount?.uid else {
            return 0
        }
        let coins = (try? await profileRepository.fetchProfile(userId: userId))?.coins ?? 0
        var landed = 0
        for pending in queue {
            guard let task = (try? await taskRepository.task(id: pending.taskId, userId: userId)) ?? nil,
                  !task.completed
            else { continue }
            // The local context was stamped at tap time in the widget - an
            // overnight drain must not shift evening behavior into morning.
            _ = await completionStore.setCompleted(
                task, completed: true, currentCoins: coins, userId: userId,
                localContext: pending.context
            )
            landed += 1
        }
        return landed
    }
}
