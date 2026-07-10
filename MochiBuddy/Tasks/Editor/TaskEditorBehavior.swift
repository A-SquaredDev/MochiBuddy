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

    /// The quick chips in the When section.
    enum DateOption: String {
        case noDate
        case today
        case tomorrow
        case pick
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

    /// One weekday toggle in the custom-repeat row.
    struct DayChip: Equatable, Identifiable {
        /// Calendar weekday number (1 = Sunday … 7 = Saturday).
        let id: Int
        let label: String
        let accessibilityLabel: String
        var isOn: Bool
    }

    struct UIState: UpdatableStruct, Equatable {
        var isEditing = false
        var title = ""
        var canSave = false
        /// "Overdue by 2 days" — edit mode only.
        var overdueBanner: String?
        var dateOptions: [ChoiceChip] = []
        var selectedDateId = DateOption.today.rawValue
        var hasDate = true
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
        /// Non-empty only while the custom repeat cadence is selected.
        var repeatDayOptions: [DayChip] = []
        var notes = ""
        var isWorking = false
    }

    enum ViewAction {
        case load
        case titleChanged(String)
        case selectDateOption(String)
        case timeTapped
        case clearTimeTapped
        case dateChanged(Date)
        case timeChanged(Date)
        case selectPriority(String)
        case selectList(String)
        case selectRepeat(String)
        case toggleRepeatDay(Int)
        case notesChanged(String)
        case saveTapped
        case snoozeTapped
        case deleteTapped
    }

    enum NavigationEvent {
        case done
    }
}
