//
//  DeleteSubActiveBehavior.swift
//  MochiBuddy
//

import Foundation

enum DeleteSubActiveBehavior {

    struct UIState: UpdatableStruct, Equatable {
        /// "$29.99/yr" — billing that survives account deletion.
        var priceLine = "your subscription price"
        var acknowledged = false
    }

    enum ViewAction {
        case load
        case toggleAcknowledged
        case deleteAnywayTapped
        case cancelTapped
    }

    enum NavigationEvent {
        case showFinalConfirm
        case close
    }
}
