//
//  YouRouter.swift
//  MochiBuddy
//
//  One router for the You tab and its sub-screens (settings sub-flow —
//  the flow-coordinator scoping from the routing doc). Creates each
//  screen's ViewModel with its dependencies and drives NavController.
//

import SwiftUI

@MainActor
protocol YouRouting: BackRouting {
    func navigateToBedtime()
    func navigateToNotifications()
    func navigateToAppleReminders()
    func navigateToVacation()
    func navigateToManageLists()
    func navigateToStats()
    func navigateToDeleteWarn()
    func navigateToDeleteSubscriptionWarning()
    func navigateToDeleteConfirm()
    func navigateBack()
    /// "Keep my account" / cancel anywhere in the delete flow — back to You.
    func exitDeleteFlow()
    /// Signed out or account deleted — back to the onboarding flow.
    func exitToOnboarding()
}

@MainActor
final class YouRouter: YouRouting {

    private let navController: NavController
    private let container: AppContainer

    init(navController: NavController, container: AppContainer) {
        self.navController = navController
        self.container = container
    }

    /// Root of the tab — the You screen.
    func start() -> AnyView {
        let viewModel = YouViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            listRepository: container.listRepository,
            membershipStore: container.membershipStore,
            themeStore: container.themeStore
        )
        return AnyView(YouView(viewModel: viewModel, router: self))
    }

    func navigateToBedtime() {
        let viewModel = BedtimeSettingsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository
        )
        navController.navigate(
            route: AdHocRoute(key: "you.bedtime"),
            view: AnyView(BedtimeSettingsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToNotifications() {
        let viewModel = NotificationPrefsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            permissionService: container.notificationPermissionService
        )
        navController.navigate(
            route: AdHocRoute(key: "you.notifications"),
            view: AnyView(NotificationPrefsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToAppleReminders() {
        let viewModel = ReminderSettingsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            remindersGateway: container.remindersGateway
        )
        navController.navigate(
            route: AdHocRoute(key: "you.reminders"),
            view: AnyView(ReminderSettingsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToVacation() {
        let viewModel = VacationViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository
        )
        navController.navigate(
            route: AdHocRoute(key: "you.vacation"),
            view: AnyView(VacationView(viewModel: viewModel, router: self))
        )
    }

    func navigateToManageLists() {
        let viewModel = ManageListsViewModel(
            authRepository: container.authRepository,
            listRepository: container.listRepository
        )
        navController.navigate(
            route: AdHocRoute(key: "you.lists"),
            view: AnyView(ManageListsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToStats() {
        let viewModel = StatsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository
        )
        navController.navigate(
            route: AdHocRoute(key: "you.stats"),
            view: AnyView(StatsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToDeleteWarn() {
        let viewModel = DeleteWarnViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            membershipStore: container.membershipStore
        )
        navController.navigate(
            route: AdHocRoute(key: "you.deleteWarn"),
            view: AnyView(DeleteWarnView(viewModel: viewModel, router: self))
        )
    }

    func navigateToDeleteSubscriptionWarning() {
        let viewModel = DeleteSubActiveViewModel(membershipStore: container.membershipStore)
        navController.navigate(
            route: AdHocRoute(key: "you.deleteSubActive"),
            view: AnyView(DeleteSubActiveView(viewModel: viewModel, router: self))
        )
    }

    func navigateToDeleteConfirm() {
        let viewModel = DeleteConfirmViewModel(
            authRepository: container.authRepository,
            accountEraser: container.accountEraser
        )
        navController.navigate(
            route: AdHocRoute(key: "you.deleteConfirm"),
            view: AnyView(DeleteConfirmView(viewModel: viewModel, router: self))
        )
    }

    func navigateBack() {
        navController.popBackStack()
    }

    func exitDeleteFlow() {
        navController.popToRoot()
    }

    func exitToOnboarding() {
        container.session.phase = .flow
    }
}
