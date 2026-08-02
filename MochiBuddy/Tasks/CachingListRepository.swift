//
//  CachingListRepository.swift
//  MochiBuddy
//
//  Decorator over ListRepository (the CachingUserProfileRepository
//  pattern): serves the list set from memory instantly and refreshes from
//  the source in the background at most once per TTL. Every in-app list
//  write already flows through this protocol, so write-through keeps the
//  cache coherent; only cross-device edits are ever momentarily stale.
//  Before this cache, fetchLists ran as a billed server query from a
//  dozen call sites (every editor open, every tab load, every
//  observation-inputs build).
//

import Foundation

final class CachingListRepository: ListRepository {

    private let wrapped: ListRepository
    private let refreshTTL: TimeInterval
    private let now: () -> Date

    private var cachedUserId: String?
    private var cached: [TaskList]?
    /// Bumped on every cache mutation so an in-flight background refresh
    /// that started earlier can't clobber newer local state.
    private var version = 0
    private var lastRefreshAt: Date?
    private(set) var refreshTask: Task<Void, Never>?

    init(
        wrapping wrapped: ListRepository,
        refreshTTL: TimeInterval = 5 * 60,
        now: @escaping () -> Date = { .now }
    ) {
        self.wrapped = wrapped
        self.refreshTTL = refreshTTL
        self.now = now
    }

    func fetchLists(userId: String) async throws -> [TaskList] {
        if cachedUserId == userId, let cached {
            FirestoreReadLog.recordCacheHit(Self.self)
            refreshInBackground(userId: userId)
            return cached
        }
        let fetched = try await wrapped.fetchLists(userId: userId)
        version += 1
        cachedUserId = userId
        cached = fetched
        lastRefreshAt = now()
        return fetched
    }

    private func refreshInBackground(userId: String) {
        guard refreshTask == nil else { return }
        if let lastRefreshAt, now().timeIntervalSince(lastRefreshAt) < refreshTTL {
            return
        }
        lastRefreshAt = now()
        let startVersion = version
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            guard let fetched = try? await self?.wrapped.fetchLists(userId: userId),
                  let self, version == startVersion, cachedUserId == userId
            else { return }
            cached = fetched
        }
    }

    /// Applies an in-app write to the cached copy (write-through).
    private func mutate(_ userId: String, _ change: (inout [TaskList]) -> Void) {
        guard cachedUserId == userId, var lists = cached else { return }
        change(&lists)
        version += 1
        cached = lists.sorted { $0.order < $1.order }
    }

    @discardableResult
    func createList(name: String, colorHex: String, icon: String, order: Int, userId: String) async throws -> TaskList {
        let created = try await wrapped.createList(
            name: name, colorHex: colorHex, icon: icon, order: order, userId: userId
        )
        mutate(userId) { $0.append(created) }
        return created
    }

    func renameList(id: String, name: String, userId: String) async throws {
        try await wrapped.renameList(id: id, name: name, userId: userId)
        mutate(userId) { lists in
            if let index = lists.firstIndex(where: { $0.id == id }) {
                lists[index].name = name
            }
        }
    }

    func updateListColor(id: String, colorHex: String, userId: String) async throws {
        try await wrapped.updateListColor(id: id, colorHex: colorHex, userId: userId)
        mutate(userId) { lists in
            if let index = lists.firstIndex(where: { $0.id == id }) {
                lists[index].colorHex = colorHex
            }
        }
    }

    func deleteList(id: String, userId: String) async throws {
        try await wrapped.deleteList(id: id, userId: userId)
        mutate(userId) { lists in
            lists.removeAll { $0.id == id }
        }
    }

    func saveOrder(ids: [String], userId: String) async throws {
        try await wrapped.saveOrder(ids: ids, userId: userId)
        // Mirror the persisted reorder: index in `ids` becomes the order.
        mutate(userId) { lists in
            for (index, id) in ids.enumerated() {
                if let position = lists.firstIndex(where: { $0.id == id }) {
                    lists[position].order = index
                }
            }
        }
    }
}
