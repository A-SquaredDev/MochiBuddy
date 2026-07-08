//
//  OnboardingRouter.swift
//  MochiBuddy
//
//  One router for the whole onboarding flow (a tightly-coupled multi-step
//  wizard — the flow-coordinator scoping from the routing doc). Creates
//  each screen's ViewModel with its dependencies and drives NavController.
//

import SwiftUI

@MainActor
protocol OnboardingRouting: AnyObject {
    func navigateToMeetMochi()
    func navigateToFirstTask()
    func navigateToFlavorPicker()
    func navigateToBedtime()
    func navigateToNotificationPrimer()
    func navigateToAppleReminders()
    func navigateToAccount()
    func navigateToPaywall()
    func navigateToFinish()
    func navigateToWelcomeBack(_ summary: ReturningAccountSummary)
    func navigateToLapsedGate()
    func navigateToRestoreFound(_ purchase: RestorablePurchase)
    func navigateToRestoreSuccess()
    func navigateBack()
    func restartOnboarding()
    func finishOnboarding()
}

@MainActor
final class OnboardingRouter: OnboardingRouting {

    private let navController: NavController
    private let container: AppContainer
    private let onboardingStore: OnboardingStore

    init(navController: NavController, container: AppContainer) {
        self.navController = navController
        self.container = container
        self.onboardingStore = OnboardingStore(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            themeStore: container.themeStore
        )
    }

    /// Root of the flow — splash.
    func start() -> AnyView {
        let viewModel = SplashViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            membershipStore: container.membershipStore
        )
        return AnyView(SplashView(viewModel: viewModel, router: self))
    }

    func navigateToMeetMochi() {
        navController.navigate(
            route: AdHocRoute(key: "meetMochi"),
            view: AnyView(MeetMochiView(viewModel: MeetMochiViewModel(), router: self))
        )
    }

    func navigateToFirstTask() {
        let viewModel = FirstTaskViewModel(onboardingStore: onboardingStore)
        navController.navigate(
            route: AdHocRoute(key: "firstTask"),
            view: AnyView(FirstTaskView(viewModel: viewModel, router: self))
        )
    }

    func navigateToFlavorPicker() {
        let viewModel = FlavorPickerViewModel(onboardingStore: onboardingStore)
        navController.navigate(
            route: AdHocRoute(key: "flavor"),
            view: AnyView(FlavorPickerView(viewModel: viewModel, router: self))
        )
    }

    func navigateToBedtime() {
        let viewModel = BedtimeViewModel(onboardingStore: onboardingStore)
        navController.navigate(
            route: AdHocRoute(key: "bedtime"),
            view: AnyView(BedtimeView(viewModel: viewModel, router: self))
        )
    }

    func navigateToNotificationPrimer() {
        let viewModel = NotificationPrimerViewModel(
            permissionService: container.notificationPermissionService,
            onboardingStore: onboardingStore
        )
        navController.navigate(
            route: AdHocRoute(key: "notifications"),
            view: AnyView(NotificationPrimerView(viewModel: viewModel, router: self))
        )
    }

    func navigateToAppleReminders() {
        let viewModel = AppleRemindersViewModel(
            remindersGateway: container.remindersGateway,
            onboardingStore: onboardingStore
        )
        navController.navigate(
            route: AdHocRoute(key: "reminders"),
            view: AnyView(AppleRemindersView(viewModel: viewModel, router: self))
        )
    }

    func navigateToAccount() {
        let viewModel = AccountViewModel(
            authRepository: container.authRepository,
            onboardingStore: onboardingStore,
            membershipStore: container.membershipStore
        )
        navController.navigate(
            route: AdHocRoute(key: "account"),
            view: AnyView(AccountView(viewModel: viewModel, router: self))
        )
    }

    func navigateToPaywall() {
        let viewModel = PaywallViewModel(
            membershipStore: container.membershipStore,
            onboardingStore: onboardingStore
        )
        navController.navigate(
            route: AdHocRoute(key: "paywall"),
            view: AnyView(PaywallView(viewModel: viewModel, router: self))
        )
    }

    func navigateToFinish() {
        navController.navigate(
            route: AdHocRoute(key: "finish"),
            view: AnyView(FinishView(router: self))
        )
    }

    func navigateToWelcomeBack(_ summary: ReturningAccountSummary) {
        let viewModel = WelcomeBackViewModel(
            summary: summary,
            membershipStore: container.membershipStore
        )
        navController.navigate(
            route: AdHocRoute(key: "welcomeBack"),
            view: AnyView(WelcomeBackView(viewModel: viewModel, router: self))
        )
    }

    func navigateToLapsedGate() {
        let viewModel = LapsedGateViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            membershipStore: container.membershipStore
        )
        navController.navigate(
            route: AdHocRoute(key: "lapsedGate"),
            view: AnyView(LapsedGateView(viewModel: viewModel, router: self))
        )
    }

    func navigateToRestoreFound(_ purchase: RestorablePurchase) {
        let viewModel = RestoreFoundViewModel(
            purchase: purchase,
            membershipStore: container.membershipStore,
            authRepository: container.authRepository,
            profileRepository: container.profileRepository
        )
        navController.navigate(
            route: AdHocRoute(key: "restoreFound"),
            view: AnyView(RestoreFoundView(viewModel: viewModel, router: self))
        )
    }

    func navigateToRestoreSuccess() {
        navController.navigate(
            route: AdHocRoute(key: "restoreSuccess"),
            view: AnyView(RestoreSuccessView(router: self))
        )
    }

    func navigateBack() {
        navController.popBackStack()
    }

    /// "Not you? Switch account" — drop the session and run first-run again.
    func restartOnboarding() {
        try? container.authRepository.signOut()
        Task { @MainActor in
            _ = try? await container.authRepository.ensureSession()
            navController.replaceStack(
                with: AnyView(MeetMochiView(viewModel: MeetMochiViewModel(), router: self)),
                route: AdHocRoute(key: "meetMochi")
            )
        }
    }

    func finishOnboarding() {
        Task { @MainActor in
            await onboardingStore.markComplete()
            container.session.phase = .home
        }
    }
}
