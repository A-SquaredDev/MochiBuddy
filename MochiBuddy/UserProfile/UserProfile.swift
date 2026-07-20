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

    /// Whether the local wall-clock time falls inside the window (which
    /// usually wraps past midnight, e.g. 22:00 → 07:00).
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard startMinutes != endMinutes else { return false }
        return startMinutes < endMinutes
            ? minutes >= startMinutes && minutes < endMinutes
            : minutes >= startMinutes || minutes < endMinutes
    }
}

/// Whether vacation is in force at an instant - the ONE definition of
/// auto-expiry, shared by the live mood engine and the forecast so a
/// scheduled ping can never disagree with mood(now) about it.
enum VacationSchedule {
    static func isActive(mode: Bool, resumeAt: Date?, at now: Date) -> Bool {
        guard mode else { return false }
        // Open-ended (no end date) stays on until turned off.
        guard let resumeAt else { return true }
        return now < resumeAt
    }
}

/// "How chatty should Mochi be?" - the overall nudge cadence dial.
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
    /// Opt-in lock-screen privacy: task names show by default (normal for
    /// a reminders app); on, reminders and rundowns go nameless.
    var hideTaskNames = false

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
    /// Last local day with ≥1 completion - drives the streak.
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

    /// Vacation with auto-expiry applied - use this, not the raw flag.
    func vacationActive(at now: Date) -> Bool {
        VacationSchedule.isActive(mode: vacationMode, resumeAt: vacationResumeAt, at: now)
    }
}
