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

    /// The in-flight drain, memoized so concurrent callers coalesce onto
    /// one landing. A Home refresh racing the RootView drain awaits the
    /// SAME task instead of seeing an empty queue and reading pre-drain
    /// Firestore state.
    private var inFlight: Task<Int, Never>?

    /// Persist every queued widget completion. Ids whose tasks are gone
    /// or already done drop silently. Returns how many landed. Awaiting
    /// this is the barrier that keeps a refresh() from reading pre-drain
    /// completion counts.
    @discardableResult
    func drain() async -> Int {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<Int, Never> { [weak self] in
            defer { self?.inFlight = nil }
            return await self?.performDrain() ?? 0
        }
        inFlight = task
        return await task.value
    }

    private func performDrain() async -> Int {
        // Signed out: leave the queue for a signed-in launch - a tap must
        // never be lost to a drain that cannot land it.
        guard let userId = authRepository.currentAccount?.uid else {
            return 0
        }
        let queue = WidgetStateStore.drainCompletions(defaults: defaults)
        guard !queue.isEmpty else {
            return 0
        }
        let coins = (try? await profileRepository.fetchProfile(userId: userId))?.coins ?? 0
        var landed = 0
        for pending in queue {
            guard let task = (try? await taskRepository.task(id: pending.taskId, userId: userId)) ?? nil,
                  !task.completed
            else { continue }
            // The local context and tap instant were stamped at tap time in
            // the widget - an overnight drain must not shift evening
            // behavior into morning, and completedAt must not book a stale
            // tap into today's momentum window. Entries queued before
            // tappedAt existed fall back to the instant the context implies.
            _ = await completionStore.setCompleted(
                task, completed: true, currentCoins: coins, userId: userId,
                localContext: pending.context,
                completedAt: pending.tappedAt ?? pending.context?.approximateInstant
            )
            landed += 1
        }
        return landed
    }
}
