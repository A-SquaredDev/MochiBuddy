//
//  WelcomeBackViewModel.swift
//  MochiBuddy
//
//  R · Welcome back — account recognised, Mochi drooped a little while
//  away. Continue routes on membership state: active purchase found →
//  restore, otherwise → the lapsed gate.
//

import Foundation

final class WelcomeBackViewModel: ObservableStateViewModel<
    WelcomeBackBehavior.UIState,
    WelcomeBackBehavior.ViewAction,
    WelcomeBackBehavior.NavigationEvent
> {

    private let summary: ReturningAccountSummary
    private let membershipStore: MembershipStore

    init(summary: ReturningAccountSummary, membershipStore: MembershipStore) {
        self.summary = summary
        self.membershipStore = membershipStore
        super.init(initialState: WelcomeBackBehavior.UIState())
    }

    override func triggerAsync(_ action: WelcomeBackBehavior.ViewAction) async {
        switch action {
        case .load:
            setUIState(
                uiState
                    .updating(\.name, to: summary.name)
                    .updating(\.detail, to: summary.detail)
                    .updating(\.providerLabel, to: summary.providerLabel)
            )

        case .continueTapped:
            state.isWorking = true
            let status = await membershipStore.currentStatus()
            switch status {
            case .active, .trial:
                state.isWorking = false
                setNavigationEvent(.enterApp)
            case .lapsed, .notSubscribed:
                if let purchase = await membershipStore.restorablePurchase() {
                    state.isWorking = false
                    setNavigationEvent(.showRestoreFound(purchase))
                } else {
                    state.isWorking = false
                    setNavigationEvent(.showLapsedGate)
                }
            }

        case .switchAccountTapped:
            setNavigationEvent(.restartOnboarding)
        }
    }
}
