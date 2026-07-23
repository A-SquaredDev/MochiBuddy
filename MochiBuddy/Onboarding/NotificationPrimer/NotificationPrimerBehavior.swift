//
//  NotificationPrimerBehavior.swift
//  MochiBuddy
//

import Foundation

enum NotificationPrimerBehavior {

    struct UIState: UpdatableStruct, Equatable {
        /// The pet's chosen name (named in step 2, so it's already set).
        var petName = "Mochi"
        var isRequesting = false
    }

    enum ViewAction {
        case enableTapped
        case laterTapped
    }

    enum NavigationEvent {
        case next
    }
}
