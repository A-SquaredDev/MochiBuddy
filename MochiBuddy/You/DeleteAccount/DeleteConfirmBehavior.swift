//
//  DeleteConfirmBehavior.swift
//  MochiBuddy
//

import Foundation

enum DeleteConfirmBehavior {

    /// Which fresh-login proof this account needs before deletion.
    enum ReauthMethod: Equatable {
        case apple
        case google
        /// Guest (anonymous) accounts have no credential to re-verify.
        case none
    }

    struct UIState: UpdatableStruct, Equatable {
        var method: ReauthMethod = .none
        var isVerified = false
        /// SHA-256 nonce the Sign in with Apple request must carry.
        var hashedNonce: String?
        var isWorking = false
        var errorMessage: String?
    }

    enum ViewAction {
        case load
        case appleCompleted(idToken: String)
        case appleFailed(message: String)
        case googleTapped
        case deleteTapped
        case keepTapped
        case dismissError
    }

    enum NavigationEvent {
        /// Everything is gone — leave to the onboarding flow.
        case deleted
        case close
    }
}
