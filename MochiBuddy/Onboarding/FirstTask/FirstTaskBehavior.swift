//
//  FirstTaskBehavior.swift
//  MochiBuddy
//

import Foundation

enum FirstTaskBehavior {

    /// A rough slot for the first task's reminder - onboarding-light, no
    /// wheel picker. The task is always seeded due today; a slot adds a
    /// time so the first task can actually remind.
    enum TimeChoice: CaseIterable, Equatable {
        case morning
        case afternoon
        case evening
        case noTime

        var label: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .evening: "Evening"
            case .noTime: "No time"
            }
        }

        /// Minutes since local midnight; nil leaves the task date-only.
        var minuteOfDay: Int? {
            switch self {
            case .morning: 9 * 60
            case .afternoon: 13 * 60
            case .evening: 18 * 60
            case .noTime: nil
            }
        }
    }

    struct UIState: UpdatableStruct, Equatable {
        var title = ""
        var suggestions: [String] = ["Drink water", "Call mum", "Pay rent"]
        var timeChoice: TimeChoice = .noTime
        var canAdd = false
        var isSaving = false
        /// Used on the very next screen after the naming beat - instant
        /// proof the choice took.
        var petName = "Mochi"
    }

    enum ViewAction {
        case titleChanged(String)
        case suggestionTapped(String)
        case timeChoiceTapped(TimeChoice)
        case addTapped
        case skipTapped
    }

    enum NavigationEvent {
        case next
    }
}
