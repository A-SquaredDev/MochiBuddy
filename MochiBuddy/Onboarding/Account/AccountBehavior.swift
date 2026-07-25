//
//  AccountBehavior.swift
//  MochiBuddy
//

import Foundation

enum AccountBehavior {

    struct UIState: UpdatableStruct, Equatable {
        /// The pet's chosen name (named in step 2, so it's already set).
        var petName = "Mochi"
        /// SHA-256 nonce the Sign in with Apple request must carry.
        var hashedNonce: String?
        var isWorking = false
        var errorMessage: String?
        var showGoogleUnavailable = false
        /// Non-nil when the session is already a provider account (the
        /// landing sign-in happened earlier in this run) - the footer
        /// swaps the provider buttons for a Continue button.
        var signedInDetail: String?
    }

    enum ViewAction {
        case load
        case appleCompleted(idToken: String, fullName: PersonNameComponents?)
        case appleFailed(message: String)
        case googleTapped
        case continueTapped
        case dismissError
        case dismissGoogleUnavailable
    }

    enum NavigationEvent: Equatable {
        /// Never-subscribed: on to the trial paywall, as always.
        case next
        /// Already entitled but onboarding incomplete: skip the paywall.
        case skipToFinish
        /// Restored a completed, entitled account: straight into the app.
        case enterApp
        /// Restored a completed account whose membership expired.
        case showLapsedGate
        case showRestoreFound(RestorablePurchase)
    }
}
