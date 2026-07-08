//
//  UserProfile.swift
//  MochiBuddy
//
//  Domain model for users/{uid}. Immutable-by-default struct; mutations are
//  deliberate copies.
//

import Foundation

struct BedtimeWindow: Equatable {
    /// Minutes since local midnight ("wall-clock intention", not an instant).
    var startMinutes: Int
    var endMinutes: Int

    static let standard = BedtimeWindow(startMinutes: 22 * 60, endMinutes: 7 * 60)
}

struct UserProfile: Equatable {
    let id: String
    var displayName: String?
    var authProvider: String?
    var createdAt: Date?
    var timezone: String?
    var bedtime: BedtimeWindow
    var themeId: String?
    var coins: Int
    var streakCount: Int
    var isSubscribed: Bool
    var trialEndsAt: Date?
    var onboardingComplete: Bool
    var notificationsEnabled: Bool?
    var importedReminderListIds: [String]
}
