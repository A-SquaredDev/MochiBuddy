//
//  TaskEditorBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum TaskEditorBehavior {

    enum PickerTarget: Equatable {
        case none
        case date
        case time
    }

    /// Chip dot color — status tones resolve against the theme in the View.
    enum ChipDot: Equatable {
        case none
        case custom(Color)
        case warn
        case danger
    }

    struct ChoiceChip: Equatable, Identifiable {
        let id: String
        let label: String
        var dot: ChipDot = .none
    }

    struct UIState: UpdatableStruct, Equatable {
        var isEditing = false
        var title = ""
        var canSave = false
        /// "Overdue by 2 days" — edit mode only.
        var overdueBanner: String?
        var hasDate = false
        var dateText = "Add date"
        var date = Date()
        var hasTime = false
        var timeText = "Add time"
        var time = Date()
        var activePicker: PickerTarget = .none
        var priorityOptions: [ChoiceChip] = []
        var selectedPriorityId = TaskPriority.med.rawValue
        var listOptions: [ChoiceChip] = []
        var selectedListId = "inbox"
        var repeatOptions: [ChoiceChip] = []
        var selectedRepeatId = "none"
        var notes = ""
        var isWorking = false
    }

    enum ViewAction {
        case load
        case titleChanged(String)
        case dateTapped
        case timeTapped
        case noDateTapped
        case dateChanged(Date)
        case timeChanged(Date)
        case selectPriority(String)
        case selectList(String)
        case selectRepeat(String)
        case notesChanged(String)
        case saveTapped
        case snoozeTapped
        case deleteTapped
    }

    enum NavigationEvent {
        case done
    }
}
