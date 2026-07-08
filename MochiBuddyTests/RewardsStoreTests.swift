//
//  RewardsStoreTests.swift
//  MochiBuddyTests
//
//  Coins are earned, never bought — and never farmable. Streaks extend on
//  consecutive days, hold within a day, and restart after a gap.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("RewardsStore · coins")
struct RewardsCoinsTests {

    @Test("a completion pays the flat rate")
    func flatRate() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.coinsDelta == RewardsStore.coinsPerTask)
        #expect(repo.coinDeltas == [RewardsStore.coinsPerTask])
    }

    @Test("undoing a completion claws the coins back symmetrically")
    func revokeSymmetric() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        let delta = await store.revokeCompletion(currentCoins: 50, userId: "user1")
        #expect(delta == -RewardsStore.coinsPerTask)
        #expect(repo.coinDeltas == [-RewardsStore.coinsPerTask])
    }

    @Test("clawback never drives the balance below zero")
    func revokeClamped() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        let delta = await store.revokeCompletion(currentCoins: 4, userId: "user1")
        #expect(delta == -4)
    }

    @Test("clawback with an empty balance is a no-op — no write at all")
    func revokeEmptyBalance() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        let delta = await store.revokeCompletion(currentCoins: 0, userId: "user1")
        #expect(delta == 0)
        #expect(repo.coinDeltas.isEmpty)
    }

    @Test("toggle-spam nets zero coins — complete/undo/complete/undo")
    func toggleSpamNetsZero() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        var coins = 0
        for _ in 0..<3 {
            coins += (await store.awardCompletion(userId: "user1")).coinsDelta
            coins += await store.revokeCompletion(currentCoins: coins, userId: "user1")
        }
        #expect(coins == 0)
    }

    @Test("spending treats decrements by the cost")
    func spend() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        await store.spendCoins(30, userId: "user1")
        #expect(repo.coinDeltas == [-30])
    }
}

@Suite("RewardsStore · streaks")
struct RewardsStreakTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }

    private func store(profile: UserProfile) -> (RewardsStore, StubProfileRepository) {
        let repo = StubProfileRepository()
        repo.profile = profile
        return (RewardsStore(profileRepository: repo), repo)
    }

    @Test("the very first completion starts a 1-day streak")
    func firstCompletion() async {
        let (store, repo) = store(profile: makeProfile())
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.streak == 1)
        #expect(outcome.bestStreak == 1)
        #expect(repo.savedStreaks.last?.count == 1)
    }

    @Test("a second completion the same day holds the streak")
    func sameDayHolds() async {
        let (store, _) = store(profile: makeProfile(streak: 3, bestStreak: 5, lastActiveDate: today))
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.streak == 3)
        #expect(outcome.bestStreak == 5)
    }

    @Test("completing on consecutive days extends the streak")
    func consecutiveExtends() async {
        let (store, _) = store(profile: makeProfile(streak: 3, bestStreak: 3, lastActiveDate: yesterday))
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.streak == 4)
        #expect(outcome.bestStreak == 4, "a new record must update the best")
    }

    @Test("a missed day restarts the streak at 1 but preserves the record")
    func gapRestarts() async {
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        let (store, _) = store(profile: makeProfile(streak: 12, bestStreak: 12, lastActiveDate: threeDaysAgo))
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.streak == 1)
        #expect(outcome.bestStreak == 12, "the best streak is a record, not a live counter")
    }

    @Test("a profile that claims a streak but no lastActiveDate starts fresh")
    func missingLastActive() async {
        let (store, _) = store(profile: makeProfile(streak: 7, bestStreak: 7, lastActiveDate: nil))
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.streak == 1)
        #expect(outcome.bestStreak == 7)
    }

    @Test("lastActiveDate is stamped to the start of today")
    func stampsToday() async {
        let (store, repo) = store(profile: makeProfile())
        _ = await store.awardCompletion(userId: "user1")
        #expect(repo.savedStreaks.last?.lastActiveDate == today)
    }

    @Test("a same-day completion with a zero streak still records at least 1")
    func zeroStreakSameDay() async {
        // Corrupt-ish state: active today but streak 0 — never report 0 after completing.
        let (store, _) = store(profile: makeProfile(streak: 0, lastActiveDate: today))
        let outcome = await store.awardCompletion(userId: "user1")
        #expect(outcome.streak == 1)
    }
}
