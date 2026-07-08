//
//  RewardsStore.swift
//  MochiBuddy
//
//  Coins & streak business logic. Coins are earn-only (flat per task —
//  priority scaling would invite mislabeling), still awarded for overdue
//  completions (clearing a late task is the recovery moment we most want
//  to reward). One sink: treats.
//

import Foundation

@MainActor
final class RewardsStore {

    static let coinsPerTask = 10

    struct CompletionOutcome {
        let coinsDelta: Int
        let streak: Int
        let bestStreak: Int
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
        if let lastActive = profile?.lastActiveDate.map(calendar.startOfDay(for:)) {
            if lastActive == today {
                streak = max(previousStreak, 1)
            } else if calendar.date(byAdding: .day, value: 1, to: lastActive) == today {
                streak = previousStreak + 1
            } else {
                streak = 1
            }
        } else {
            streak = 1
        }
        let best = max(previousBest, streak)

        try? await profileRepository.incrementCoins(by: Self.coinsPerTask, userId: userId)
        try? await profileRepository.saveStreak(count: streak, best: best, lastActiveDate: today, userId: userId)
        return CompletionOutcome(coinsDelta: Self.coinsPerTask, streak: streak, bestStreak: best)
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
