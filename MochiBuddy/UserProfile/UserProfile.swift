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

    /// A zero-length window is never allowed (doc edge case) - a collided
    /// picker or corrupt doc falls back to the default window at every
    /// persistence boundary, never to "no quiet hours at all".
    var sanitized: BedtimeWindow {
        startMinutes == endMinutes ? .standard : self
    }

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

/// Vacation-mode tuning (design doc: Vacation mode → Constants).
/// Remote-tunable via RemoteTuning, set once at launch.
enum VacationConstants {
    /// Fixed-mode date-picker default trip length.
    static var defaultDays = 7
    /// Re-entry wake target - the content anchor.
    static var graceWake: Double = 58
    /// Grace-buffer decay window on re-entry.
    static var graceDecay: TimeInterval = 24 * 3600
    /// Open-ended in-app "still away?" threshold.
    static var checkinDays = 14
    /// Open-ended hard auto-expiry cap - a forgotten toggle can't silently
    /// kill the app's value forever.
    static var maxDays = 30
}

/// Whether vacation is in force at an instant - the ONE definition of
/// auto-expiry, shared by the live mood engine and the forecast so a
/// scheduled ping can never disagree with mood(now) about it.
enum VacationSchedule {

    /// When this vacation ends: the chosen date, or the hard cap for
    /// open-ended. Nil only when no start was recorded (legacy open-ended
    /// entries keep their old un-capped behavior).
    static func effectiveEnd(startedAt: Date?, resumeAt: Date?) -> Date? {
        if let resumeAt { return resumeAt }
        guard let startedAt else { return nil }
        return startedAt.addingTimeInterval(TimeInterval(VacationConstants.maxDays) * 24 * 3600)
    }

    static func isActive(mode: Bool, startedAt: Date?, resumeAt: Date?, at now: Date) -> Bool {
        guard mode else { return false }
        guard let end = effectiveEnd(startedAt: startedAt, resumeAt: resumeAt) else { return true }
        return now < end
    }
}

struct NotificationPrefs: Equatable {
    var taskReminders = true
    var morningRundown = true
    var moodDips = false
    var bedtimeSilence = true
    /// Opt-in lock-screen privacy: task names show by default (normal for
    /// a reminders app); on, reminders and rundowns go nameless.
    var hideTaskNames = false
    /// The Sunday letter invitation (Feature 3). Reading never depends on
    /// it - the letter always arrives in-app.
    var weeklyLetter = true
    /// Minutes since local midnight when a dated-but-untimed task's
    /// reminder fires. Nil means the standard morning slot.
    var defaultReminderMinutes: Int?

    static let standardDefaultReminderMinutes = 9 * 60

    /// The effective wall-clock minute for date-only reminders.
    var effectiveDefaultReminderMinutes: Int {
        defaultReminderMinutes ?? Self.standardDefaultReminderMinutes
    }

    static let standard = NotificationPrefs()
}

struct UserProfile: Equatable {
    let id: String
    var displayName: String?
    var authProvider: String?
    var createdAt: Date?
    /// The pet's name (default "Mochi"). Sanitized at every persistence
    /// boundary; replaces "Mochi" in pet-referential copy only, never brand.
    var mochiName: String = PetNameSanitizer.defaultName
    /// Date-only YYYY-MM-DD stamped when the naming beat completes - the
    /// literal "day you met", distinct from `createdAt`. Write-once,
    /// enforced by Firestore security rules; rendered verbatim (no timezone
    /// math can ever shift it).
    var adoptedOn: String? = nil
    var timezone: String?
    var bedtime: BedtimeWindow
    var themeId: String?
    var coins: Int
    var streakCount: Int
    var bestStreakCount: Int
    /// Date-only YYYY-MM-DD the stored best-streak record was FIRST
    /// reached (Personal Layer, Feature 2). Updated atomically with
    /// `bestStreakCount`, and only on a strict exceed - equal values
    /// never overwrite the date; as an active record run advances daily
    /// the date advances with it. Legacy records are never assigned a
    /// guessed date (nil until a new record stamps it).
    var bestStreakAchievedOn: String? = nil
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
    /// When the current vacation began - drives the open-ended auto-expiry
    /// cap, the long-run check-in, and the re-entry bucket window.
    var vacationStartedAt: Date?
    var importedReminderListIds: [String]
    /// Append-only log of vacation + lapse intervals (Personal Layer,
    /// Feature 4) - momentum eligibility. Synced because deterministic
    /// hysteresis needs identical inputs on every device.
    var observationIntervals: [ObservationInterval] = []
    /// When the interval log began for this profile; days before it have
    /// unknown eligibility (the honest-fallback rule keeps momentum silent
    /// over them).
    var observationLogSince: Date? = nil

    /// Vacation with auto-expiry applied - use this, not the raw flag.
    func vacationActive(at now: Date) -> Bool {
        VacationSchedule.isActive(
            mode: vacationMode, startedAt: vacationStartedAt,
            resumeAt: vacationResumeAt, at: now
        )
    }
}
