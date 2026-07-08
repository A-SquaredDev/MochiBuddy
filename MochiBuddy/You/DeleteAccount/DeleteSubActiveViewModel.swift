//
//  DeleteSubActiveViewModel.swift
//  MochiBuddy
//
//  Delete account · 2 — the purchase belongs to the Apple ID, not our
//  account record: deleting the account does NOT stop billing. Requires
//  an explicit acknowledgment before continuing.
//

import Foundation

final class DeleteSubActiveViewModel: ObservableStateViewModel<
    DeleteSubActiveBehavior.UIState,
    DeleteSubActiveBehavior.ViewAction,
    DeleteSubActiveBehavior.NavigationEvent
> {

    private let membershipStore: MembershipStore

    init(membershipStore: MembershipStore) {
        self.membershipStore = membershipStore
        super.init(initialState: DeleteSubActiveBehavior.UIState())
    }

    override func triggerAsync(_ action: DeleteSubActiveBehavior.ViewAction) async {
        switch action {
        case .load:
            guard case .active(let plan, _) = await membershipStore.currentStatus() else { return }
            let option = await membershipStore.planOptions().first { $0.plan == plan }
            if let option {
                state.priceLine = "\(option.localizedPrice)/\(plan == .yearly ? "yr" : "mo")"
            }

        case .toggleAcknowledged:
            state.acknowledged.toggle()

        case .deleteAnywayTapped:
            guard uiState.acknowledged else { return }
            setNavigationEvent(.showFinalConfirm)

        case .cancelTapped:
            setNavigationEvent(.close)
        }
    }
}
