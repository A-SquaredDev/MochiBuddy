//
//  NotificationPrefsBehavior.swift
//  MochiBuddy
//

import Foundation

enum NotificationPrefsBehavior {

    /// OS-level delivery problems worth a banner: denied kills everything;
    /// provisional (the skipped-primer floor) delivers silently, which
    /// reads as "notifications don't work" to the user.
    enum PermissionIssue: Equatable {
        case denied
        case provisional
    }

    struct UIState: UpdatableStruct, Equatable {
        /// The pet's chosen name - "Mochi" until the profile loads.
        var petName = "Mochi"
        var taskReminders = true
        /// Wall-clock slot for dated-but-untimed task reminders, carried
        /// as a Date for the picker (only hour/minute matter).
        var defaultReminderTime = Date()
        var morningRundown = true
        var moodDips = false
        var bedtimeSilence = true
        var bedtimeSilenceSub = ""
        /// Opt-in lock-screen privacy: hide task names from notifications.
        var hideTaskNames = false
        /// The Sunday letter invitation (Feature 3).
        var weeklyLetter = true
        /// OS-level delivery problem - nil means fully authorized.
        var permissionIssue: PermissionIssue?
    }

    enum ViewAction {
        case load
        case setTaskReminders(Bool)
        case setDefaultReminderTime(Date)
        case setMorningRundown(Bool)
        case setMoodDips(Bool)
        case setBedtimeSilence(Bool)
        case setHideTaskNames(Bool)
        case setWeeklyLetter(Bool)
        /// Provisional only: shows the real system prompt (provisional has
        /// not consumed the one-shot dialog).
        case enableFullNotifications
    }
}
