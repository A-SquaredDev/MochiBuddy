//
//  CachingTaskRepository.swift
//  MochiBuddy
//
//  Decorator over TaskRepository (the CachingUserProfileRepository
//  pattern): serves the incomplete set, the recent-completions window, and
//  completion stats from memory, with write-through on every mutating
//  method - all in-app task writes already funnel through this protocol,
//  so the cache stays coherent by construction. Cross-device edits land on
//  the next foreground refresh, exactly like the profile cache.
//
//  Coherence rules:
//  - Every mutation applies to the cached arrays synchronously, then fires
//    onMutation (wired to the observation-inputs memo) - a consumer can
//    never read pre-mutation history after a write returns.
//  - A version counter guards async installs: a fetch that was in flight
//    when a write-through landed returns its rows to the caller but never
//    clobbers the newer cache.
//  - Everything is scoped to one uid; a different uid is a cold cache.
//  - The FromServer barrier variants always hit the source and refresh the
//    cache with what the server said.
//

import Foundation

final class CachingTaskRepository: TaskRepository {

    private let wrapped: TaskRepository
    private let now: () -> Date

    private var cachedUserId: String?
    private var incomplete: [TaskItem]?
    /// Completed tasks, newest first. Two coverage dimensions: everything
    /// on/after coverageSince (when set), and at least the newest
    /// coverageLimit items (when > 0).
    private var completed: [TaskItem]?
    private var completedCoverageSince: Date?
    private var completedCoverageLimit = 0
    /// Completion stats covering everything on/after statsSince.
    private var stats: [CompletedTaskStat]?
    private var statsSince: Date?
    /// Bumped on every cache mutation (the profile cache's clobber guard).
    private var version = 0

    /// Fired after every write-through mutation. AppContainer points this
    /// at ObservationService.invalidateInputs so the 132-day memo can
    /// never serve pre-mutation history.
    var onMutation: (() -> Void)?

    init(wrapping wrapped: TaskRepository, now: @escaping () -> Date = { .now }) {
        self.wrapped = wrapped
        self.now = now
    }

    /// The foreground pipeline's one real refresh: drop everything, warm
    /// the hottest query eagerly; completions and stats refill lazily on
    /// their next consumer (one fetch each, once, instead of per surface).
    func refresh(userId: String) async {
        dropCache(userId: userId)
        let startVersion = version
        guard let fetched = try? await wrapped.incompleteTasks(userId: userId) else { return }
        if version == startVersion, cachedUserId == userId {
            incomplete = fetched
        }
    }

    // MARK: - Reads

    func incompleteTasks(userId: String) async throws -> [TaskItem] {
        scope(userId)
        if let incomplete {
            FirestoreReadLog.recordCacheHit(Self.self)
            return incomplete
        }
        let startVersion = version
        let fetched = try await wrapped.incompleteTasks(userId: userId)
        if version == startVersion, cachedUserId == userId {
            incomplete = fetched
        }
        return fetched
    }

    func completedTasks(limit: Int, userId: String) async throws -> [TaskItem] {
        scope(userId)
        if let completed, coversLimit(limit) {
            FirestoreReadLog.recordCacheHit(Self.self)
            return Array(completed.prefix(limit))
        }
        let startVersion = version
        let fetched = try await wrapped.completedTasks(limit: limit, userId: userId)
        if version == startVersion, cachedUserId == userId {
            completed = fetched
            completedCoverageLimit = limit
            completedCoverageSince = nil
        }
        return fetched
    }

    func completedTasks(since: Date, userId: String) async throws -> [TaskItem] {
        scope(userId)
        if let completed, coversSince(since) {
            FirestoreReadLog.recordCacheHit(Self.self)
            return completed.filter { ($0.completedAt ?? .distantPast) >= since }
        }
        let startVersion = version
        let fetched = try await wrapped.completedTasks(since: since, userId: userId)
        if version == startVersion, cachedUserId == userId {
            completed = fetched
            completedCoverageSince = since
            completedCoverageLimit = 0
        }
        return fetched
    }

    func completedTaskStats(since: Date, userId: String) async throws -> [CompletedTaskStat] {
        scope(userId)
        if let stats, let anchor = statsSince, anchor <= since {
            FirestoreReadLog.recordCacheHit(Self.self)
            return stats.filter { $0.completedAt >= since }
        }
        let startVersion = version
        let fetched = try await wrapped.completedTaskStats(since: since, userId: userId)
        if version == startVersion, cachedUserId == userId {
            stats = fetched
            statsSince = since
        }
        return fetched
    }

    func completedTasksPage(
        limit: Int, after cursor: CompletedPageCursor?, userId: String
    ) async throws -> CompletedTasksPage {
        scope(userId)
        // Page one is the newest-first prefix - exactly what the limit
        // coverage can prove. Older pages always pass through: they are
        // on-demand, bounded, and don't fit the newest-first cache model.
        if cursor == nil, let completed, coversLimit(limit) {
            FirestoreReadLog.recordCacheHit(Self.self)
            let items = Array(completed.prefix(limit))
            let moreMayExist = completed.count > limit
                || !(completedCoverageLimit > 0 && completed.count < completedCoverageLimit)
            let nextCursor: CompletedPageCursor? = moreMayExist
                ? items.last.flatMap { last in
                    last.completedAt.map { CompletedPageCursor(completedAt: $0, documentID: last.id) }
                }
                : nil
            return CompletedTasksPage(items: items, nextCursor: nextCursor)
        }
        let startVersion = version
        let page = try await wrapped.completedTasksPage(limit: limit, after: cursor, userId: userId)
        if cursor == nil, version == startVersion, cachedUserId == userId {
            completed = page.items
            completedCoverageLimit = limit
            completedCoverageSince = nil
        }
        return page
    }

    func completedTaskCount(since: Date, userId: String) async throws -> Int {
        try await wrapped.completedTaskCount(since: since, userId: userId)
    }

    func completedTasks(listId: String, limit: Int, userId: String) async throws -> [TaskItem] {
        try await wrapped.completedTasks(listId: listId, limit: limit, userId: userId)
    }

    func task(id: String, userId: String) async throws -> TaskItem? {
        scope(userId)
        if let hit = incomplete?.first(where: { $0.id == id })
            ?? completed?.first(where: { $0.id == id }) {
            FirestoreReadLog.recordCacheHit(Self.self)
            return hit
        }
        return try await wrapped.task(id: id, userId: userId)
    }

    func incompleteTaskCount(userId: String) async throws -> Int {
        try await wrapped.incompleteTaskCount(userId: userId)
    }

    func totalTaskCount(userId: String) async throws -> Int {
        try await wrapped.totalTaskCount(userId: userId)
    }

    // MARK: - Barrier reads (refresh the cache with server truth)

    func completedTaskStatsFromServer(since: Date, userId: String) async throws -> [CompletedTaskStat] {
        scope(userId)
        let fetched = try await wrapped.completedTaskStatsFromServer(since: since, userId: userId)
        version += 1
        stats = fetched
        statsSince = since
        return fetched
    }

    func completedTasksFromServer(since: Date, userId: String) async throws -> [TaskItem] {
        scope(userId)
        let fetched = try await wrapped.completedTasksFromServer(since: since, userId: userId)
        version += 1
        completed = fetched
        completedCoverageSince = since
        completedCoverageLimit = 0
        return fetched
    }

    func incompleteTasksFromServer(userId: String) async throws -> [TaskItem] {
        scope(userId)
        let fetched = try await wrapped.incompleteTasksFromServer(userId: userId)
        version += 1
        incomplete = fetched
        return fetched
    }

    // MARK: - Writes (write-through)

    func allocateTaskId(userId: String) -> String {
        wrapped.allocateTaskId(userId: userId)
    }

    @discardableResult
    func addTask(_ draft: TaskDraft, id: String?, userId: String) async throws -> String {
        scope(userId)
        let savedId = try await wrapped.addTask(draft, id: id, userId: userId)
        mutate {
            incomplete?.append(TaskItem(
                id: savedId,
                title: draft.title,
                notes: draft.notes,
                dueAt: draft.dueAt,
                hasTime: draft.hasTime,
                priority: draft.priority,
                listId: draft.listId,
                repeatRule: draft.repeatRule,
                completed: false,
                completedAt: nil,
                createdAt: now(),
                seriesId: draft.seriesId,
                rescheduleCount: 0,
                estimatedMinutes: draft.estimatedMinutes
            ))
        }
        return savedId
    }

    func setCompleted(
        taskId: String, completed isCompleted: Bool,
        localContext: CompletionLocalContext?, completedAt: Date?, userId: String
    ) async throws {
        scope(userId)
        try await wrapped.setCompleted(
            taskId: taskId, completed: isCompleted,
            localContext: localContext, completedAt: completedAt, userId: userId
        )
        mutate {
            if isCompleted {
                guard var task = removeIncomplete(taskId) else {
                    // Cold or unknown: the arrays can't be moved coherently,
                    // so the completion-shaped caches refill on next read.
                    invalidateCompletionCaches()
                    return
                }
                let instant = completedAt ?? now()
                task.completed = true
                task.completedAt = instant
                self.completed?.insert(task, at: 0)
                // Synthesize the stat the server would return, so the most
                // frequent action in the app never costs a history refetch.
                stats?.append(CompletedTaskStat(
                    taskId: task.id,
                    seriesId: task.seriesId,
                    completedAt: instant,
                    dueAt: task.dueAt,
                    listId: task.listId,
                    hasTime: task.hasTime,
                    isRecurring: task.repeatRule != nil || task.seriesId != nil,
                    source: .mochi,
                    rescheduleCount: task.rescheduleCount,
                    estimatedMinutes: task.estimatedMinutes,
                    localContext: localContext ?? .capture(at: instant)
                ))
            } else {
                guard let index = self.completed?.firstIndex(where: { $0.id == taskId }),
                      var task = self.completed?.remove(at: index) else {
                    invalidateCompletionCaches()
                    return
                }
                task.completed = false
                task.completedAt = nil
                incomplete?.append(task)
                stats?.removeAll { $0.taskId == taskId }
            }
        }
    }

    func updateTask(_ task: TaskItem, countingReschedule: Bool, userId: String) async throws {
        scope(userId)
        try await wrapped.updateTask(task, countingReschedule: countingReschedule, userId: userId)
        mutate {
            var updated = task
            if countingReschedule {
                updated.rescheduleCount = (updated.rescheduleCount ?? 0) + 1
            }
            if let index = incomplete?.firstIndex(where: { $0.id == task.id }) {
                incomplete?[index] = updated
            } else if let index = completed?.firstIndex(where: { $0.id == task.id }) {
                completed?[index] = updated
            } else {
                // Unknown to the cache - refill rather than guess.
                incomplete = nil
            }
        }
    }

    func snoozeTask(id: String, to newDueAt: Date, userId: String) async throws {
        scope(userId)
        try await wrapped.snoozeTask(id: id, to: newDueAt, userId: userId)
        mutate {
            restampIncomplete(id) {
                $0.dueAt = newDueAt
                $0.rescheduleCount = ($0.rescheduleCount ?? 0) + 1
            }
        }
    }

    func rollForwardTask(id: String, to newDueAt: Date, missedOccurrences: Int, userId: String) async throws {
        scope(userId)
        try await wrapped.rollForwardTask(
            id: id, to: newDueAt, missedOccurrences: missedOccurrences, userId: userId
        )
        mutate {
            restampIncomplete(id) { $0.dueAt = newDueAt }
        }
    }

    func deleteTask(id: String, userId: String) async throws {
        scope(userId)
        try await wrapped.deleteTask(id: id, userId: userId)
        mutate {
            incomplete?.removeAll { $0.id == id }
            completed?.removeAll { $0.id == id }
            stats?.removeAll { $0.taskId == id }
        }
    }

    // MARK: - Internals

    /// Any uid other than the cached one starts cold - the sign-out /
    /// account-switch invalidation is structural, not a callback.
    private func scope(_ userId: String) {
        guard cachedUserId != userId else { return }
        dropCache(userId: userId)
    }

    private func dropCache(userId: String) {
        cachedUserId = userId
        incomplete = nil
        completed = nil
        completedCoverageSince = nil
        completedCoverageLimit = 0
        stats = nil
        statsSince = nil
        version += 1
    }

    private func mutate(_ change: () -> Void) {
        version += 1
        change()
        onMutation?()
    }

    private func invalidateCompletionCaches() {
        completed = nil
        completedCoverageSince = nil
        completedCoverageLimit = 0
        stats = nil
        statsSince = nil
    }

    private func removeIncomplete(_ id: String) -> TaskItem? {
        guard let index = incomplete?.firstIndex(where: { $0.id == id }) else { return nil }
        return incomplete?.remove(at: index)
    }

    private func restampIncomplete(_ id: String, _ change: (inout TaskItem) -> Void) {
        guard let index = incomplete?.firstIndex(where: { $0.id == id }) else {
            incomplete = nil
            return
        }
        if var task = incomplete?[index] {
            change(&task)
            incomplete?[index] = task
        }
    }

    /// A since-window is covered by a since-anchor at or before it, or by
    /// a limit cache whose oldest row is strictly older than the window
    /// start (everything in the window is then among the cached newest),
    /// or by a limit cache that turned out to hold the entire history.
    private func coversSince(_ since: Date) -> Bool {
        guard let completed else { return false }
        if let anchor = completedCoverageSince, anchor <= since { return true }
        guard completedCoverageLimit > 0 else { return false }
        if completed.count < completedCoverageLimit { return true }
        if let oldest = completed.last?.completedAt, oldest < since { return true }
        return false
    }

    /// A limit is covered by a bigger cached limit, by a whole-history
    /// limit cache, or by a since-window that holds at least `limit` rows
    /// (everything outside the window is older than everything inside).
    private func coversLimit(_ limit: Int) -> Bool {
        guard let completed else { return false }
        if completedCoverageLimit >= limit { return true }
        if completedCoverageLimit > 0, completed.count < completedCoverageLimit { return true }
        if completedCoverageSince != nil, completed.count >= limit { return true }
        return false
    }
}
