//
//  SplashBehavior.swift
//  MochiBuddy
//

import Foundation

enum SplashBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var failedToStart = false
    }

    enum ViewAction {
        case load
        case retryTapped
    }

    enum NavigationEvent: Equatable {
        case showLanding
        case showWelcomeBack(ReturningAccountSummary)
        case enterApp
    }
}

/// Display-ready summary of the recognised account, passed to Welcome Back.
struct ReturningAccountSummary: Equatable {
    let name: String
    let detail: String
    let providerLabel: String
    /// The pet's chosen name from the fetched profile.
    var petName: String = "Mochi"
}
