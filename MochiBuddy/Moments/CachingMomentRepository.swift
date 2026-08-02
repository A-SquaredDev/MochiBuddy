//
//  CachingMomentRepository.swift
//  MochiBuddy
//
//  Decorator over MomentRepository (the CachingUserProfileRepository
//  pattern). Moments are append-only records with a natural-key id and the
//  one producer funnel (ensureMoment) flows through this protocol, so
//  write-through keeps the cached collection coherent - the Journal's
//  whole-collection query per visit becomes a cache hit. Cross-device
//  moments (milestones landed on another device) arrive on the TTL
//  refresh; they only ever add rows, never change them.
//

import Foundation

final class CachingMomentRepository: MomentRepository {

    private let wrapped: MomentRepository
    private let refreshTTL: TimeInterval
    private let now: () -> Date

    private var cachedUserId: String?
    private var cached: [Moment]?
    /// Bumped on every cache mutation so an in-flight background refresh
    /// that started earlier can't clobber newer local state.
    private var version = 0
    private var lastRefreshAt: Date?
    private(set) var refreshTask: Task<Void, Never>?

    init(
        wrapping wrapped: MomentRepository,
        refreshTTL: TimeInterval = 30 * 60,
        now: @escaping () -> Date = { .now }
    ) {
        self.wrapped = wrapped
        self.refreshTTL = refreshTTL
        self.now = now
    }

    func moments(userId: String) async throws -> [Moment] {
        scope(userId)
        if let cached {
            FirestoreReadLog.recordCacheHit(Self.self)
            refreshInBackground(userId: userId)
            return cached
        }
        let fetched = try await wrapped.moments(userId: userId)
        version += 1
        cached = fetched
        lastRefreshAt = now()
        return fetched
    }

    func ensureMoment(_ moment: Moment, userId: String) async {
        scope(userId)
        await wrapped.ensureMoment(moment, userId: userId)
        // Create-only: an existing natural key never changes content, so
        // the write-through mirrors the rules' first-writer-wins.
        guard cachedUserId == userId, var cached,
              !cached.contains(where: { $0.id == moment.id })
        else { return }
        version += 1
        cached.append(moment)
        self.cached = cached.sorted { $0.occurredOn > $1.occurredOn }
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
            guard let fetched = try? await self?.wrapped.moments(userId: userId),
                  let self, version == startVersion, cachedUserId == userId
            else { return }
            cached = fetched
        }
    }

    /// Any uid other than the cached one starts cold - the sign-out /
    /// account-switch invalidation is structural, not a callback.
    private func scope(_ userId: String) {
        guard cachedUserId != userId else { return }
        cachedUserId = userId
        cached = nil
        lastRefreshAt = nil
        version += 1
    }
}
