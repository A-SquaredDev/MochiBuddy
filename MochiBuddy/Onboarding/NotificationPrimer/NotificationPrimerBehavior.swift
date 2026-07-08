//
//  NotificationPrimerBehavior.swift
//  MochiBuddy
//

import Foundation

enum NotificationPrimerBehavior {

    struct UIState: UpdatableStruct, Equatable {
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
