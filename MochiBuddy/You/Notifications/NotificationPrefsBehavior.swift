//
//  NotificationPrefsBehavior.swift
//  MochiBuddy
//

import Foundation

enum NotificationPrefsBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var taskReminders = true
        var morningRundown = true
        var moodDips = false
        var bedtimeSilence = true
        var bedtimeSilenceSub = ""
        /// Opt-in lock-screen privacy: hide task names from notifications.
        var hideTaskNames = false
        /// Notifications denied at the OS level - show the Settings hint.
        var systemDenied = false
    }

    enum ViewAction {
        case load
        case setTaskReminders(Bool)
        case setMorningRundown(Bool)
        case setMoodDips(Bool)
        case setBedtimeSilence(Bool)
        case setHideTaskNames(Bool)
    }
}
