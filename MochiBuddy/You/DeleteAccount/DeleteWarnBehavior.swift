//
//  DeleteWarnBehavior.swift
//  MochiBuddy
//

import Foundation

enum DeleteWarnBehavior {

    struct ErasedItem: Equatable, Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
    }

    struct UIState: UpdatableStruct, Equatable {
        var items: [ErasedItem] = []
        var isChecking = false
    }

    enum ViewAction {
        case load
        case continueTapped
        case keepTapped
    }

    enum NavigationEvent {
        /// An active subscription keeps billing — show the warning first.
        case showSubscriptionWarning
        case showFinalConfirm
        case close
    }
}
