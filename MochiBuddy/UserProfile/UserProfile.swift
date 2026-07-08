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

/// "How chatty should Mochi be?" — the overall nudge cadence dial.
enum NudgeLevel: String, CaseIterable, Equatable {
    case rarely
    case balanced
    case chatty
}

struct NotificationPrefs: Equatable {
    var level: NudgeLevel = .balanced
    var taskReminders = true
    var morningRundown = true
    var moodDips = false
    var bedtimeSilence = true

    static let standard = NotificationPrefs()
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
    var bestStreakCount: Int
    /// Last local day with ≥1 completion — drives the streak.
    var lastActiveDate: Date?
    var isSubscribed: Bool
    var trialEndsAt: Date?
    var onboardingComplete: Bool
    var notificationsEnabled: Bool?
    var notificationPrefs: NotificationPrefs
    var soundEnabled: Bool
    var vacationMode: Bool
    /// When set, vacation mode auto-resumes at this instant.
    var vacationResumeAt: Date?
    var importedReminderListIds: [String]
}
