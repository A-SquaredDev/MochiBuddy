//
//  SignInBehavior.swift
//  MochiBuddy
//

import Foundation

enum SignInBehavior {

    struct UIState: UpdatableStruct, Equatable {
        /// SHA-256 nonce the Sign in with Apple request must carry.
        var hashedNonce: String?
        var isWorking = false
        var errorMessage: String?
        var showGoogleUnavailable = false
        /// The provider account has no Mochi profile - offer fresh setup.
        var showNoAccountFound = false
    }

    enum ViewAction {
        case load
        case appleCompleted(idToken: String, fullName: PersonNameComponents?)
        case appleFailed(message: String)
        case googleTapped
        case noAccountFoundConfirmed
        case dismissError
        case dismissGoogleUnavailable
    }

    enum NavigationEvent: Equatable {
        case enterApp
        case showLapsedGate
        case showRestoreFound(RestorablePurchase)
        case startOnboarding
    }
}
