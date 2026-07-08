//
//  RestoreFoundViewModel.swift
//  MochiBuddy
//
//  R2 · Restore membership — an active purchase was found on this
//  Apple ID; restoring is free and instant.
//

import Foundation

final class RestoreFoundViewModel: ObservableStateViewModel<
    RestoreFoundBehavior.UIState,
    RestoreFoundBehavior.ViewAction,
    RestoreFoundBehavior.NavigationEvent
> {

    private let purchase: RestorablePurchase
    private let membershipStore: MembershipStore
    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository

    init(
        purchase: RestorablePurchase,
        membershipStore: MembershipStore,
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository
    ) {
        self.purchase = purchase
        self.membershipStore = membershipStore
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        super.init(initialState: RestoreFoundBehavior.UIState())
    }

    override func triggerAsync(_ action: RestoreFoundBehavior.ViewAction) async {
        switch action {
        case .load:
            let planName = purchase.plan == .yearly ? "Yearly" : "Monthly"
            var renews = "Active membership"
            if let renewsAt = purchase.renewsAt {
                renews = "Renews \(renewsAt.formatted(date: .abbreviated, time: .omitted))"
            }
            setUIState(
                uiState
                    .updating(\.planLine, to: "Mochi \(planName) · Active")
                    .updating(\.renewsLine, to: renews)
            )

        case .restoreTapped:
            state.isWorking = true
            try? await membershipStore.restore(purchase)
            if let userId = authRepository.currentAccount?.uid {
                try? await profileRepository.saveMembershipMirror(
                    isSubscribed: true,
                    trialEndsAt: nil,
                    userId: userId
                )
            }
            state.isWorking = false
            setNavigationEvent(.showSuccess)

        case .differentAppleIdTapped:
            state.showAppleIdNote = true

        case .dismissAppleIdNote:
            state.showAppleIdNote = false
        }
    }
}
