//
//  AccountBehavior.swift
//  MochiBuddy
//

import Foundation

enum AccountBehavior {

    struct UIState: UpdatableStruct, Equatable {
        /// SHA-256 nonce the Sign in with Apple request must carry.
        var hashedNonce: String?
        var isWorking = false
        var errorMessage: String?
        var showGoogleUnavailable = false
    }

    enum ViewAction {
        case load
        case appleCompleted(idToken: String, fullName: PersonNameComponents?)
        case appleFailed(message: String)
        case googleTapped
        case dismissError
        case dismissGoogleUnavailable
    }

    enum NavigationEvent {
        case next
    }
}
