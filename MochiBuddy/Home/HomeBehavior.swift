//
//  HomeBehavior.swift
//  MochiBuddy
//

import Foundation

enum HomeBehavior {

    struct TodoUIItem: Equatable, Identifiable {
        let id: String
        let title: String
        let meta: String
        let state: TodoRowState
        let chip: String
    }

    struct TreatUIItem: Equatable, Identifiable {
        let id: String
        let name: String
        let emoji: String
        let liftText: String      // "+18"
        let durationText: String  // "lasts ~3 hr"
        let costText: String      // "Give · 30 ¢"
        let canAfford: Bool
    }

    /// Identifiable wrapper so the editor sheet presents via sheet(item:).
    struct EditingTask: Equatable, Identifiable {
        let task: TaskItem
        var id: String { task.id }
    }

    struct UIState: UpdatableStruct, Equatable {
        var greeting = "Hi, friend"
        var subGreeting = "Let's keep Mochi happy"
        var coins = 0
        var streakDays = 0
        var baseline: Double = MoodEngine.Constants.anchor
        var buffer: Double = 0
        /// baseline + buffer, clamped — what the pet's face shows.
        var displayedMood: Double = MoodEngine.Constants.anchor
        var moodTitle = "Mochi feels content"
        var moodSub = "Clear a task to make it beam"
        var petSquishTrigger = 0
        var quickAddText = ""
        var todayItems: [TodoUIItem] = []
        var leftText = "0 left"
        var showEmptyToday = false
        var showTreats = false
        var treats: [TreatUIItem] = []
        var bufferLabel = "+0 / 30"
        var petActionMeta = "+8 · lasts ~15 min"
        var editingTask: EditingTask?
    }

    enum ViewAction {
        case refresh
        /// Timer beat — re-derives the decaying buffer, no fetching.
        case tick
        case petTapped
        case treatsTapped
        case dismissTreats
        case giveTreat(String)
        case quickAddChanged(String)
        case quickAddSubmitted
        case toggleTask(String)
        case taskTapped(String)
        case editorDismissed
    }
}
