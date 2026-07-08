//
//  AppleRemindersBehavior.swift
//  MochiBuddy
//

import Foundation

enum AppleRemindersBehavior {

    enum Phase: Equatable {
        /// Explains the import; the EventKit prompt hasn't fired yet.
        case primer
        /// Access granted — the user picks which lists to bring in.
        case picking
    }

    struct ListUIItem: Equatable, Identifiable {
        let id: String
        let name: String
        let countText: String
        var isOn: Bool
    }

    struct UIState: UpdatableStruct, Equatable {
        var phase: Phase = .primer
        var lists: [ListUIItem] = []
        var isWorking = false
        var ctaTitle = "Bring them in"
    }

    enum ViewAction {
        case primaryTapped
        case toggleList(String)
        case skipTapped
    }

    enum NavigationEvent {
        case next
    }
}
