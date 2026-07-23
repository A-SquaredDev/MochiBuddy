//
//  FirstTaskBehavior.swift
//  MochiBuddy
//

import Foundation

enum FirstTaskBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var title = ""
        var suggestions: [String] = ["Drink water", "Call mum", "Pay rent"]
        var canAdd = false
        var isSaving = false
        /// Used on the very next screen after the naming beat - instant
        /// proof the choice took.
        var petName = "Mochi"
    }

    enum ViewAction {
        case titleChanged(String)
        case suggestionTapped(String)
        case addTapped
        case skipTapped
    }

    enum NavigationEvent {
        case next
    }
}
