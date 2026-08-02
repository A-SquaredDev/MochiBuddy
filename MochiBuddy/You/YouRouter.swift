//
//  YouRouter.swift
//  MochiBuddy
//
//  One router for the You tab and its sub-screens (settings sub-flow -
//  the flow-coordinator scoping from the routing doc). Creates each
//  screen's ViewModel with its dependencies and drives NavController.
//

import SwiftUI

@MainActor
protocol YouRouting: BackRouting {
    func navigateToBedtime()
    func navigateToStats()
    /// The "?" behind the Best Hours pair - the general chart explainer.
    func navigateToBestHoursHelp()
    func navigateToNotifications()
    func navigateToAppleReminders()
    func navigateToVacation()
    func navigateToManageLists()
    func navigateToDeleteWarn()
    func navigateToDeleteSubscriptionWarning()
    func navigateToDeleteConfirm()
    func navigateBack()
    /// "Keep my account" / cancel anywhere in the delete flow - back to You.
    func exitDeleteFlow()
    /// Signed out or account deleted - back to the onboarding flow.
    func exitToOnboarding()
    /// Lapsed "Wake Mochi" - back through the flow to the reactivate gate.
    func wakeMochi()
    #if DEBUG
    func navigateToDevScheduler()
    #endif
}

@MainActor
final class YouRouter: YouRouting {

    private let navController: NavController
    private let container: AppContainer

    init(navController: NavController, container: AppContainer) {
        self.navController = navController
        self.container = container
    }

    /// Root of the tab - the You screen.
    func start() -> AnyView {
        let viewModel = YouViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            listRepository: container.listRepository,
            membershipStore: container.membershipStore,
            membershipSession: container.membershipSession,
            themeStore: container.themeStore,
            relay: container.notificationOrchestrator,
            petIdentityStore: container.petIdentityStore
        )
        return AnyView(YouView(
            viewModel: viewModel,
            router: self,
            coordinator: container.tabCoordinator
        ))
    }

    func wakeMochi() {
        container.session.flowEntry = .splash
        container.session.phase = .flow
    }

    #if DEBUG
    func navigateToDevScheduler() {
        let viewModel = DevSchedulerViewModel(
            orchestrator: container.notificationOrchestrator,
            scheduler: container.notificationScheduler,
            membershipStore: container.membershipStore,
            membershipSession: container.membershipSession,
            observationService: container.observationService,
            observationLedger: container.observationLedger,
            letterService: container.letterCompositionService,
            memoriesService: container.memoriesService,
            suggestionLedger: container.suggestionLedger
        )
        navController.navigate(
            route: AdHocRoute(key: "you.devScheduler"),
            view: AnyView(DevSchedulerView(viewModel: viewModel, router: self))
        )
    }
    #endif

    func navigateToBedtime() {
        let viewModel = BedtimeSettingsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            relay: container.notificationOrchestrator
        )
        navController.navigate(
            route: AdHocRoute(key: "you.bedtime"),
            view: AnyView(BedtimeSettingsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToStats() {
        let viewModel = StatsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            petIdentityStore: container.petIdentityStore,
            observationService: container.observationService,
            observationLedger: container.observationLedger
        )
        navController.navigate(
            route: AdHocRoute(key: "you.stats"),
            view: AnyView(StatsView(viewModel: viewModel, router: self))
        )
    }

    func navigateToBestHoursHelp() {
        navController.navigate(
            route: AdHocRoute(key: "you.stats.help"),
            view: AnyView(BestHoursHelpView(
                petName: container.petIdentityStore.name, router: self
            ))
        )
    }

    func navigateToNotifications() {
        let viewModel = NotificationPrefsViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            permissionService: container.notificationPermissionService,
            relay: container.notificationOrchestrator
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
            profileRepository: container.profileRepository,
            relay: container.notificationOrchestrator,
            reentryService: container.vacationReentryService,
            intervalRecorder: container.observationIntervalRecorder
        )
        navController.navigate(
            route: AdHocRoute(key: "you.vacation"),
            view: AnyView(VacationView(viewModel: viewModel, router: self))
        )
    }


    func navigateToManageLists() {
        let viewModel = ManageListsViewModel(
            authRepository: container.authRepository,
            listRepository: container.listRepository,
            membershipSession: container.membershipSession,
            petName: container.petIdentityStore.name
        )
        navController.navigate(
            route: AdHocRoute(key: "you.lists"),
            view: AnyView(ManageListsView(viewModel: viewModel, router: self))
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
            accountEraser: container.accountEraser,
            observationLedger: container.observationLedger,
            callbackLedger: container.callbackLedger,
            suggestionLedger: container.suggestionLedger,
            nudgeLedger: container.nudgeLedger,
            relay: container.notificationOrchestrator,
            membershipStore: container.membershipStore
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

    /// Sign-out and account deletion leave through here: Landing, not
    /// splash, so no replacement anonymous account is minted.
    func exitToOnboarding() {
        container.session.flowEntry = .landing
        container.session.phase = .flow
    }
}
