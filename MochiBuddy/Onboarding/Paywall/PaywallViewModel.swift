//
//  PaywallViewModel.swift
//  MochiBuddy
//
//  9 · Membership — subscription-only gate placed after the value moment.
//  Hooks first, then plans with live store pricing; 7 days free, no
//  freemium tier.
//

import Foundation

final class PaywallViewModel: ObservableStateViewModel<
    PaywallBehavior.UIState,
    PaywallBehavior.ViewAction,
    PaywallBehavior.NavigationEvent
> {

    private let membershipStore: MembershipStore
    private let onboardingStore: OnboardingStore

    private var options: [MembershipPlanOption] = [.defaultYearly, .defaultMonthly]

    init(membershipStore: MembershipStore, onboardingStore: OnboardingStore) {
        self.membershipStore = membershipStore
        self.onboardingStore = onboardingStore
        super.init(initialState: PaywallBehavior.UIState())
    }

    override func triggerAsync(_ action: PaywallBehavior.ViewAction) async {
        switch action {
        case .load:
            options = await membershipStore.planOptions()
            rebuildPlanState()

        case .selectPlan(let id):
            state.selectedPlanId = id
            rebuildPlanState()

        case .startTrialTapped:
            let plan = MembershipPlan(rawValue: uiState.selectedPlanId) ?? .yearly
            state.isPurchasing = true
            do {
                try await membershipStore.startTrial(plan: plan)
                var trialEndsAt: Date?
                if case .trial(let endsAt) = await membershipStore.currentStatus() {
                    trialEndsAt = endsAt
                }
                await onboardingStore.recordMembership(isSubscribed: true, trialEndsAt: trialEndsAt)
                state.isPurchasing = false
                setNavigationEvent(.next)
            } catch MembershipStoreError.cancelled {
                state.isPurchasing = false
            } catch {
                state.isPurchasing = false
                state.restoreMessage = "The purchase didn't go through. Please try again."
            }

        case .restoreTapped:
            state.isRestoring = true
            if let purchase = await membershipStore.restorablePurchase() {
                try? await membershipStore.restore(purchase)
                await onboardingStore.recordMembership(isSubscribed: true, trialEndsAt: nil)
                state.isRestoring = false
                setNavigationEvent(.next)
            } else {
                state.isRestoring = false
                state.restoreMessage = "No previous Mochi membership was found on this Apple ID."
            }

        case .dismissRestoreMessage:
            state.restoreMessage = nil
        }
    }

    private func rebuildPlanState() {
        let monthlyPrice = options.first { $0.plan == .monthly }?.price
        let plans = options.map { PlanCardModel.from($0, monthlyPrice: monthlyPrice) }

        let selected = options.first { $0.plan.rawValue == uiState.selectedPlanId } ?? options.first
        let ctaTitle = selected?.hasIntroTrial == true ? "Start my 7 days free" : "Start my membership"
        var ctaSubtitle = "Cancel anytime"
        if let selected {
            let per = selected.plan == .yearly ? "yr" : "mo"
            ctaSubtitle = selected.hasIntroTrial
                ? "Then \(selected.localizedPrice)/\(per) · cancel anytime, keep the free days"
                : "\(selected.localizedPrice)/\(per) · cancel anytime"
        }

        setUIState(
            uiState
                .updating(\.plans, to: plans)
                .updating(\.ctaTitle, to: ctaTitle)
                .updating(\.ctaSubtitle, to: ctaSubtitle)
        )
    }
}
