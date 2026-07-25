//
//  RewardsStore.swift
//  MochiBuddy
//
//  Coins & streak business logic. Coins are earn-only (flat per task -
//  priority scaling would invite mislabeling), still awarded for overdue
//  completions (clearing a late task is the recovery moment we most want
//  to reward). One sink: treats.
//

import Foundation

@MainActor
final class RewardsStore {

    /// Flat per task by design (priority-scaling invites mislabeling).
    /// Remote-tunable, set once at launch.
    static var coinsPerTask = 10

    struct CompletionOutcome {
        let coinsDelta: Int
        let streak: Int
        let bestStreak: Int
        /// False when today already held the streak - a milestone only
        /// celebrates on the completion that actually reaches it.
        let streakExtended: Bool
    }

    private let profileRepository: UserProfileRepository
    private let calendar: Calendar

    init(profileRepository: UserProfileRepository, calendar: Calendar = .current) {
        self.profileRepository = profileRepository
        self.calendar = calendar
    }

    /// A task was completed: award coins and extend the streak.
    func awardCompletion(userId: String) async -> CompletionOutcome {
        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let previousStreak = profile?.streakCount ?? 0
        let previousBest = profile?.bestStreakCount ?? 0

        let today = calendar.startOfDay(for: .now)
        let streak: Int
        var extended = true
        if let lastActive = profile?.lastActiveDate.map(calendar.startOfDay(for:)) {
            if lastActive == today {
                streak = max(previousStreak, 1)
                extended = false
            } else if calendar.date(byAdding: .day, value: 1, to: lastActive) == today {
                streak = previousStreak + 1
            } else {
                streak = 1
            }
        } else {
            streak = 1
        }
        let best = max(previousBest, streak)
        // The bestStreakAchievedOn contract (Personal Layer, Feature 2):
        // stamped only on a STRICT exceed, atomically with the count, in
        // the streak engine's own calendar. Equal never overwrites; an
        // advancing record run re-stamps daily (the date the stored
        // record was first reached); legacy records are never guessed.
        let bestAchievedOn = streak > previousBest
            ? AdoptedOnDate.string(from: today)
            : profile?.bestStreakAchievedOn

        try? await profileRepository.incrementCoins(by: Self.coinsPerTask, userId: userId)
        try? await profileRepository.saveStreak(
            count: streak, best: best, bestAchievedOn: bestAchievedOn,
            lastActiveDate: today, userId: userId
        )
        return CompletionOutcome(
            coinsDelta: Self.coinsPerTask, streak: streak, bestStreak: best, streakExtended: extended
        )
    }

    /// A completion was undone: claw the coins back (never below zero) so
    /// toggle-spam can't farm the balance. The streak is left alone.
    func revokeCompletion(currentCoins: Int, userId: String) async -> Int {
        let delta = -min(Self.coinsPerTask, max(0, currentCoins))
        guard delta != 0 else { return 0 }
        try? await profileRepository.incrementCoins(by: delta, userId: userId)
        return delta
    }

    /// Treats: coins out, comfort in.
    func spendCoins(_ cost: Int, userId: String) async {
        try? await profileRepository.incrementCoins(by: -cost, userId: userId)
    }
}
