//
//  NotificationPrefsBehavior.swift
//  MochiBuddy
//

import Foundation

enum NotificationPrefsBehavior {

    /// One option in the "how chatty" selector.
    struct LevelOption: Equatable, Identifiable {
        let id: String
        let label: String
    }

    struct UIState: UpdatableStruct, Equatable {
        var levelOptions: [LevelOption] = []
        var selectedLevelId = ""
        var taskReminders = true
        var morningRundown = true
        var moodDips = false
        var bedtimeSilence = true
        var bedtimeSilenceSub = ""
        /// Notifications denied at the OS level — show the Settings hint.
        var systemDenied = false
    }

    enum ViewAction {
        case load
        case selectLevel(String)
        case setTaskReminders(Bool)
        case setMorningRundown(Bool)
        case setMoodDips(Bool)
        case setBedtimeSilence(Bool)
    }
}
