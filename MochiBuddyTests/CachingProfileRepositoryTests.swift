//
//  CachingProfileRepositoryTests.swift
//  MochiBuddyTests
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("CachingUserProfileRepository")
struct CachingProfileRepositoryTests {

    @Test("First fetch delegates, second serves the cached copy")
    func secondFetchServesCache() async throws {
        let stub = StubProfileRepository()
        stub.profile = makeProfile(coins: 5)
        let repo = CachingUserProfileRepository(wrapping: stub)

        let first = try await repo.fetchProfile(userId: "user1")
        #expect(first?.coins == 5)

        // The source changing without a write through the repo must not
        // affect the synchronous answer - that's the cache hit.
        stub.profile = makeProfile(coins: 99)
        let second = try await repo.fetchProfile(userId: "user1")
        #expect(second?.coins == 5)
    }

    @Test("A cache hit still refreshes from the source once the TTL passes")
    func backgroundRefreshUpdatesCache() async throws {
        let stub = StubProfileRepository()
        stub.profile = makeProfile(coins: 5)
        // TTL zero: every hit is past the TTL, the pre-TTL behavior.
        let repo = CachingUserProfileRepository(wrapping: stub, refreshTTL: 0)

        _ = try await repo.fetchProfile(userId: "user1")
        stub.profile = makeProfile(coins: 99)
        _ = try await repo.fetchProfile(userId: "user1")

        await repo.refreshTask?.value
        let refreshed = try await repo.fetchProfile(userId: "user1")
        #expect(refreshed?.coins == 99)
    }

    @Test("Inside the TTL a cache hit costs ZERO source reads")
    func ttlSuppressesBackgroundRefresh() async throws {
        let stub = StubProfileRepository()
        let repo = CachingUserProfileRepository(wrapping: stub, refreshTTL: 300)

        _ = try await repo.fetchProfile(userId: "user1")
        #expect(stub.fetchCount == 1)

        for _ in 0..<10 {
            _ = try await repo.fetchProfile(userId: "user1")
        }
        await repo.refreshTask?.value
        #expect(stub.fetchCount == 1,
                "the old behavior spawned a real server read on every hit - 20 to 40 per session")
    }

    @Test("The TTL expires on the injected clock, not wall time")
    func ttlExpiresWithClock() async throws {
        let stub = StubProfileRepository()
        var clock = Dates.now
        let repo = CachingUserProfileRepository(
            wrapping: stub, refreshTTL: 300, now: { clock }
        )

        _ = try await repo.fetchProfile(userId: "user1")
        _ = try await repo.fetchProfile(userId: "user1")
        await repo.refreshTask?.value
        #expect(stub.fetchCount == 1)

        clock = Dates.now.addingTimeInterval(301)
        _ = try await repo.fetchProfile(userId: "user1")
        await repo.refreshTask?.value
        #expect(stub.fetchCount == 2, "one refresh per elapsed TTL window")
    }

    @Test("Writes flow through to the cached copy")
    func writeThroughKeepsCacheCoherent() async throws {
        let stub = StubProfileRepository()
        let repo = CachingUserProfileRepository(wrapping: stub)

        _ = try await repo.fetchProfile(userId: "user1")

        var prefs = NotificationPrefs.standard
        prefs.morningRundown = false
        prefs.hideTaskNames = true
        // StubProfileRepository's saveNotificationPrefs does NOT touch its
        // profile, so a changed read can only come from the cache.
        try await repo.saveNotificationPrefs(prefs, userId: "user1")

        let fetched = try await repo.fetchProfile(userId: "user1")
        #expect(fetched?.notificationPrefs == prefs)
    }

    @Test("A different user misses the cache and delegates")
    func differentUserBypassesCache() async throws {
        let stub = StubProfileRepository()
        stub.profile = makeProfile(coins: 5)
        let repo = CachingUserProfileRepository(wrapping: stub)

        _ = try await repo.fetchProfile(userId: "user1")

        var other = makeProfile(coins: 42)
        other = UserProfile(
            id: "user2", displayName: other.displayName, authProvider: nil,
            createdAt: nil, timezone: nil, bedtime: other.bedtime, themeId: nil,
            coins: other.coins, streakCount: 0, bestStreakCount: 0,
            lastActiveDate: nil, isSubscribed: false, trialEndsAt: nil,
            onboardingComplete: true, notificationsEnabled: nil,
            notificationPrefs: .standard, soundEnabled: false,
            vacationMode: false, vacationResumeAt: nil, vacationStartedAt: nil,
            importedReminderListIds: []
        )
        stub.profile = other

        let fetched = try await repo.fetchProfile(userId: "user2")
        #expect(fetched?.id == "user2")
        #expect(fetched?.coins == 42)
    }

    @Test("Writes for another user leave the cache untouched")
    func writeForOtherUserIgnored() async throws {
        let stub = StubProfileRepository()
        stub.profile = makeProfile(coins: 5)
        let repo = CachingUserProfileRepository(wrapping: stub)

        _ = try await repo.fetchProfile(userId: "user1")
        try await repo.incrementCoins(by: 100, userId: "someone-else")

        // Stub applied the delta to its own profile, but the cached copy for
        // user1 must not have - and the cached copy wins on a hit.
        let fetched = try await repo.fetchProfile(userId: "user1")
        #expect(fetched?.coins == 5)
    }

    @Test("Bedtime write-through sanitizes like the persistence boundary")
    func bedtimeWriteThroughSanitizes() async throws {
        let stub = StubProfileRepository()
        let repo = CachingUserProfileRepository(wrapping: stub)

        _ = try await repo.fetchProfile(userId: "user1")
        try await repo.saveBedtime(
            BedtimeWindow(startMinutes: 600, endMinutes: 600), userId: "user1"
        )

        let fetched = try await repo.fetchProfile(userId: "user1")
        #expect(fetched?.bedtime == .standard)
    }
}
