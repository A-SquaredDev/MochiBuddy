//
//  WelcomeBackBehavior.swift
//  MochiBuddy
//

import Foundation

enum WelcomeBackBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var name = ""
        var detail = ""
        var providerLabel = ""
        var isWorking = false
    }

    enum ViewAction {
        case load
        case continueTapped
        case switchAccountTapped
    }

    enum NavigationEvent: Equatable {
        case enterApp
        case showLapsedGate
        case showRestoreFound(RestorablePurchase)
        case restartOnboarding
    }
}
