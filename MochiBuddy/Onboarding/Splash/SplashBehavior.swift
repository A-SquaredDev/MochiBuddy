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

    enum NavigationEvent {
        case showMeetMochi
        case showWelcomeBack(ReturningAccountSummary)
        case enterApp
    }
}

/// Display-ready summary of the recognised account, passed to Welcome Back.
struct ReturningAccountSummary: Equatable {
    let name: String
    let detail: String
    let providerLabel: String
}
