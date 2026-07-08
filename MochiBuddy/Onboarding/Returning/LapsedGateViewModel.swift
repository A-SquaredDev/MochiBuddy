//
//  LapsedGateViewModel.swift
//  MochiBuddy
//
//  R1 · Membership expired — Mochi's dozed off, nothing was deleted.
//  Shows what's waiting (tasks, streak, coins) and the plans.
//

import Foundation

final class LapsedGateViewModel: ObservableStateViewModel<
    LapsedGateBehavior.UIState,
    LapsedGateBehavior.ViewAction,
    LapsedGateBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let membershipStore: MembershipStore

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        membershipStore: MembershipStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.membershipStore = membershipStore
        super.init(initialState: LapsedGateBehavior.UIState())
    }

    override func triggerAsync(_ action: LapsedGateBehavior.ViewAction) async {
        switch action {
        case .load:
            async let stats: () = loadStats()
            let options = await membershipStore.planOptions()
            let monthlyPrice = options.first { $0.plan == .monthly }?.price
            state.plans = options.map { PlanCardModel.from($0, monthlyPrice: monthlyPrice) }
            await stats

        case .selectPlan(let id):
            state.selectedPlanId = id

        case .reactivateTapped:
            let plan = MembershipPlan(rawValue: uiState.selectedPlanId) ?? .yearly
            state.isWorking = true
            do {
                try await membershipStore.activate(plan: plan)
                if let userId = authRepository.currentAccount?.uid {
                    try? await profileRepository.saveMembershipMirror(
                        isSubscribed: true,
                        trialEndsAt: nil,
                        userId: userId
                    )
                }
                state.isWorking = false
                setNavigationEvent(.enterApp)
            } catch MembershipStoreError.cancelled {
                state.isWorking = false
            } catch {
                state.isWorking = false
                state.restoreMessage = "The purchase didn't go through. Please try again."
            }

        case .restoreTapped:
            state.isWorking = true
            if let purchase = await membershipStore.restorablePurchase() {
                state.isWorking = false
                setNavigationEvent(.showRestoreFound(purchase))
            } else {
                state.isWorking = false
                state.restoreMessage = "No previous Mochi membership was found on this Apple ID."
            }

        case .dismissRestoreMessage:
            state.restoreMessage = nil
        }
    }

    private func loadStats() async {
        guard let userId = authRepository.currentAccount?.uid else { return }
        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let taskCount = (try? await taskRepository.incompleteTaskCount(userId: userId)) ?? 0

        state.stats = [
            LapsedGateBehavior.Stat(icon: "📋", value: "\(taskCount)", label: "Tasks safe"),
            LapsedGateBehavior.Stat(icon: "🔥", value: "\(profile?.streakCount ?? 0)-day", label: "Streak kept"),
            LapsedGateBehavior.Stat(icon: "🪙", value: "\(profile?.coins ?? 0)", label: "Coins"),
        ]
    }
}
