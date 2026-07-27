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

    /// Chip dot color - status tones resolve against the theme in the View.
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

    /// The suggested-time chip (Personal Layer, Feature 5). Present only
    /// while a trigger's gates pass - no placeholder, no layout jump.
    struct SuggestionChip: Equatable {
        var label: String
        var reason: String
        var accessibilityLabel: String
        /// Tapped: the quiet "10:00 AM set" state (no dismiss affordance).
        var isConfirmed: Bool
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
        /// The pet's chosen name - construction sites that can't reach the
        /// pet identity keep the "Mochi" default.
        var petName = "Mochi"
        var title = ""
        var canSave = false
        /// "Overdue by 2 days" - edit mode only.
        var overdueBanner: String?
        var dateOptions: [ChoiceChip] = []
        var selectedDateId = DateOption.today.rawValue
        var hasDate = true
        var date = Date()
        var hasTime = false
        var timeText = "Add time"
        var time = Date()
        var suggestionChip: SuggestionChip?
        var activePicker: PickerTarget = .none
        var priorityOptions: [ChoiceChip] = []
        var selectedPriorityId = TaskPriority.med.rawValue
        var listOptions: [ChoiceChip] = []
        var selectedListId = "inbox"
        var repeatOptions: [ChoiceChip] = []
        var selectedRepeatId = "none"
        /// Non-empty only while the custom repeat cadence is selected.
        var repeatDayOptions: [DayChip] = []
        /// EFFORT pill text: the chosen level's label, or the muted unset
        /// prompt (effort guide D8). The pill shares the Priority row under
        /// its own eyebrow - never an eighth block.
        var effortText = "Set effort"
        var hasEffort = false
        /// The four magnitude levels for the pill's menu. No clock times
        /// anywhere in the picker (D1).
        var effortOptions: [ChoiceChip] = []
        var notes = ""
        var isWorking = false
        /// Recurring task: "skip this occurrence vs delete series" dialog.
        var showDeleteOptions = false
        /// Recurring task: "save this occurrence vs whole series" dialog.
        var showSaveScopeOptions = false
    }

    enum ViewAction {
        case load
        case titleChanged(String)
        case selectDateOption(String)
        case timeTapped
        case clearTimeTapped
        case dateChanged(Date)
        case timeChanged(Date)
        case suggestionTapped
        case suggestionDismissed
        case selectPriority(String)
        /// An EffortLevel rawValue, or nil for Clear.
        case selectEffort(String?)
        case selectList(String)
        case selectRepeat(String)
        case toggleRepeatDay(Int)
        case notesChanged(String)
        case saveTapped
        case snoozeTapped
        case deleteTapped
        case confirmSaveOccurrence
        case confirmSaveSeries
        case cancelSaveScope
        case confirmSkipOccurrence
        case confirmDeleteSeries
        case cancelDeleteOptions
    }

    enum NavigationEvent {
        case done
    }
}
