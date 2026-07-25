//
//  PostSignIn.swift
//  MochiBuddy
//
//  Where a successful provider sign-in should land, resolved from the
//  signed-in account's profile and entitlement. Shared by the landing
//  sign-in screen and the onboarding Account step so both route a
//  restored account the same way.
//

import Foundation

enum PostSignInDestination: Equatable {
    /// No completed profile behind this account - onboarding continues.
    case continueOnboarding
    /// Entitled but onboarding incomplete - skip the paywall step.
    case skipToFinish
    /// Completed profile, still entitled - straight into the app.
    case enterApp
    /// Completed profile, no entitlement, nothing restorable - the
    /// "Membership expired" gate carries the awareness beat.
    case lapsedGate
    /// Completed profile with an active purchase on this store account.
    case restoreFound(RestorablePurchase)
}

enum PostSignIn {

    static func resolve(
        account: AuthAccount,
        profileRepository: UserProfileRepository,
        membershipStore: MembershipStore
    ) async -> PostSignInDestination {
        let profile = try? await profileRepository.fetchProfile(userId: account.uid)
        let entitled: Bool = switch await membershipStore.currentStatus() {
        case .active, .trial, .billingGrace: true
        case .lapsed, .notSubscribed: false
        }
        guard profile?.onboardingComplete == true else {
            return entitled ? .skipToFinish : .continueOnboarding
        }
        if entitled { return .enterApp }
        // Same order Welcome Back uses: an active store purchase beats the
        // lapsed gate.
        if let purchase = await membershipStore.restorablePurchase() {
            return .restoreFound(purchase)
        }
        return .lapsedGate
    }
}
