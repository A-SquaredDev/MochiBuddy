//
//  FirstTaskBehavior.swift
//  MochiBuddy
//

import Foundation

enum FirstTaskBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var title = ""
        var suggestions: [String] = ["💧 Drink water", "📞 Call mum", "🧾 Pay rent"]
        var canAdd = false
        var isSaving = false
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
