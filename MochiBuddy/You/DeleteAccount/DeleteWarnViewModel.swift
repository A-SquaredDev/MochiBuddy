//
//  DeleteWarnViewModel.swift
//  MochiBuddy
//
//  Delete account · 1 — show exactly what's destroyed (Apple 5.1.1(v)).
//  Continue branches on the live entitlement: active billing gets its own
//  warning screen before the final confirm.
//

import Foundation

final class DeleteWarnViewModel: ObservableStateViewModel<
    DeleteWarnBehavior.UIState,
    DeleteWarnBehavior.ViewAction,
    DeleteWarnBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let membershipStore: MembershipStore

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        membershipStore: MembershipStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.membershipStore = membershipStore

        var initial = DeleteWarnBehavior.UIState()
        initial.items = Self.items(taskLine: "Everything you've captured", coins: nil, streak: nil)
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: DeleteWarnBehavior.ViewAction) async {
        switch action {
        case .load:
            await loadCounts()

        case .continueTapped:
            state.isChecking = true
            let status = await membershipStore.currentStatus()
            state.isChecking = false
            switch status {
            case .active, .trial:
                setNavigationEvent(.showSubscriptionWarning)
            case .lapsed, .notSubscribed:
                setNavigationEvent(.showFinalConfirm)
            }

        case .keepTapped:
            setNavigationEvent(.close)
        }
    }

    private func loadCounts() async {
        guard let userId = authRepository.currentAccount?.uid else { return }

        async let taskCount = try? taskRepository.totalTaskCount(userId: userId)
        async let lists = try? listRepository.fetchLists(userId: userId)
        async let profile = try? profileRepository.fetchProfile(userId: userId)

        let tasks = await taskCount ?? 0
        let listCount = await lists?.count ?? 0
        let fetched = await profile

        let taskLine = "\(tasks) task\(tasks == 1 ? "" : "s") across \(listCount + 1) list\(listCount == 0 ? "" : "s")"
        state.items = Self.items(
            taskLine: taskLine,
            coins: fetched?.coins,
            streak: fetched?.streakCount
        )
    }

    private static func items(taskLine: String, coins: Int?, streak: Int?) -> [DeleteWarnBehavior.ErasedItem] {
        [
            .init(id: "tasks", icon: "📋", title: "All tasks & lists", subtitle: taskLine),
            .init(
                id: "streak",
                icon: "🔥",
                title: "Your streak",
                subtitle: (streak ?? 0) > 0 ? "\(streak ?? 0) days — reset to zero" : "Reset to zero"
            ),
            .init(
                id: "coins",
                icon: "🪙",
                title: "Coins",
                subtitle: coins.map { "\($0) ¢ balance" } ?? "Your whole balance"
            ),
            .init(id: "mochi", icon: "🍡", title: "Mochi", subtitle: "Your companion & its history"),
        ]
    }
}
