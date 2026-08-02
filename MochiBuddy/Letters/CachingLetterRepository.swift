//
//  CachingLetterRepository.swift
//  MochiBuddy
//
//  Decorator over LetterRepository (the CachingUserProfileRepository
//  pattern). The archive is append-weekly and readAt is its one mutable
//  field, and both mutations flow through this protocol - so write-through
//  keeps the cached archive coherent and the whole-collection query that
//  used to run on EVERY foreground (refreshUnread) becomes a cache hit.
//  Cross-device composes and reads land on the TTL refresh; the barrier
//  variant (`lettersFromServer`) still always hits the server and refreshes
//  the cache with what it said, so composition correctness is untouched.
//
//  Activity markers are create-only facts: once a period is known marked,
//  that can never become false, so a per-period memo answers hasActivityMarker
//  without a doc get. Unknown periods still delegate.
//

import Foundation

final class CachingLetterRepository: LetterRepository {

    private let wrapped: LetterRepository
    private let refreshTTL: TimeInterval
    private let now: () -> Date

    private var cachedUserId: String?
    private var archive: [Letter]?
    /// Periods known to carry the engagement marker (create-only, so
    /// membership only ever grows within a uid's scope).
    private var knownMarkerPeriods: Set<String> = []
    /// Bumped on every cache mutation so an in-flight background refresh
    /// that started earlier can't clobber newer local state.
    private var version = 0
    private var lastRefreshAt: Date?
    private(set) var refreshTask: Task<Void, Never>?

    init(
        wrapping wrapped: LetterRepository,
        refreshTTL: TimeInterval = 30 * 60,
        now: @escaping () -> Date = { .now }
    ) {
        self.wrapped = wrapped
        self.refreshTTL = refreshTTL
        self.now = now
    }

    // MARK: - Archive

    func letters(userId: String) async throws -> [Letter] {
        scope(userId)
        if let archive {
            FirestoreReadLog.recordCacheHit(Self.self)
            refreshInBackground(userId: userId)
            return archive
        }
        let fetched = try await wrapped.letters(userId: userId)
        version += 1
        archive = fetched
        lastRefreshAt = now()
        return fetched
    }

    /// Barrier fetch for the composition flow: always hits the server;
    /// refreshes the cache with what it said (the freshest truth).
    func lettersFromServer(userId: String) async throws -> [Letter] {
        scope(userId)
        let fetched = try await wrapped.lettersFromServer(userId: userId)
        version += 1
        archive = fetched
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
            guard let fetched = try? await self?.wrapped.letters(userId: userId),
                  let self, version == startVersion, cachedUserId == userId
            else { return }
            archive = fetched
        }
    }

    // MARK: - Writes (write-through)

    func createLetterIfAbsent(_ letter: Letter, userId: String) async throws -> Letter {
        scope(userId)
        let winner = try await wrapped.createLetterIfAbsent(letter, userId: userId)
        if cachedUserId == userId, var archive {
            version += 1
            archive.removeAll { $0.id == winner.id }
            archive.append(winner)
            self.archive = archive.sorted { $0.periodStart > $1.periodStart }
        }
        return winner
    }

    func markRead(letterId: String, at readAt: Date, userId: String) async throws {
        try await wrapped.markRead(letterId: letterId, at: readAt, userId: userId)
        guard cachedUserId == userId,
              let index = archive?.firstIndex(where: { $0.id == letterId })
        else { return }
        version += 1
        archive?[index].readAt = readAt
    }

    // MARK: - Engagement markers

    func ensureActivityMarker(periodId: String, userId: String) async throws {
        scope(userId)
        try await wrapped.ensureActivityMarker(periodId: periodId, userId: userId)
        knownMarkerPeriods.insert(periodId)
    }

    func hasActivityMarker(periodId: String, userId: String) async throws -> Bool {
        scope(userId)
        if knownMarkerPeriods.contains(periodId) {
            FirestoreReadLog.recordCacheHit(Self.self)
            return true
        }
        let exists = try await wrapped.hasActivityMarker(periodId: periodId, userId: userId)
        if exists, cachedUserId == userId {
            knownMarkerPeriods.insert(periodId)
        }
        return exists
    }

    func hasActivityMarkerFromServer(periodId: String, userId: String) async throws -> Bool {
        scope(userId)
        // Barrier: the composition flow needs the server's answer, but a
        // confirmed marker is still a fact worth keeping.
        let exists = try await wrapped.hasActivityMarkerFromServer(periodId: periodId, userId: userId)
        if exists, cachedUserId == userId {
            knownMarkerPeriods.insert(periodId)
        }
        return exists
    }

    func flushPendingWrites() async throws {
        try await wrapped.flushPendingWrites()
    }

    // MARK: - Internals

    /// Any uid other than the cached one starts cold - the sign-out /
    /// account-switch invalidation is structural, not a callback.
    private func scope(_ userId: String) {
        guard cachedUserId != userId else { return }
        cachedUserId = userId
        archive = nil
        knownMarkerPeriods = []
        lastRefreshAt = nil
        version += 1
    }
}
