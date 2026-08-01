//
//  OnboardingRouter.swift
//  MochiBuddy
//
//  One router for the whole onboarding flow (a tightly-coupled multi-step
//  wizard - the flow-coordinator scoping from the routing doc). Creates
//  each screen's ViewModel with its dependencies and drives NavController.
//

import SwiftUI

@MainActor
protocol OnboardingRouting: AnyObject {
    func navigateToLanding()
    func navigateToSignIn()
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
            themeStore: container.themeStore,
            petIdentityStore: container.petIdentityStore
        )
    }

    /// Root of the flow - splash on cold start and session re-entries;
    /// Landing after sign-out or deletion, so no replacement anonymous
    /// account is minted for someone about to sign in or walk away.
    func start() -> AnyView {
        if container.session.flowEntry == .landing {
            return AnyView(LandingView(router: self))
        }
        let viewModel = SplashViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            membershipStore: container.membershipStore
        )
        return AnyView(SplashView(viewModel: viewModel, router: self))
    }

    func navigateToLanding() {
        navController.navigate(
            route: AdHocRoute(key: "landing"),
            view: AnyView(LandingView(router: self))
        )
    }

    func navigateToSignIn() {
        let viewModel = SignInViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            membershipStore: container.membershipStore
        )
        navController.navigate(
            route: AdHocRoute(key: "signIn"),
            view: AnyView(SignInView(viewModel: viewModel, router: self))
        )
    }

    func navigateToMeetMochi() {
        // The wizard writes every choice against the session's uid. A
        // normal cold start already has one (splash), but a Landing entry
        // after sign-out does not - mint it here, at the moment the user
        // actually commits to the wizard, never for someone who only
        // looks at Landing or heads to sign-in. Idempotent when a
        // session already exists.
        Task { @MainActor in
            _ = try? await container.authRepository.ensureSession()
        }
        let viewModel = MeetMochiViewModel(onboardingStore: onboardingStore)
        navController.navigate(
            route: AdHocRoute(key: "meetMochi"),
            view: AnyView(MeetMochiView(viewModel: viewModel, router: self))
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
            profileRepository: container.profileRepository,
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
            view: AnyView(FinishView(router: self, petName: onboardingStore.petName))
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

    /// "Not you? Switch account" - drop the session and land on Landing
    /// so the right person can sign in immediately. No replacement mint:
    /// sign-in needs no prior session, and a fresh wizard run mints at
    /// its first step.
    func restartOnboarding() {
        try? container.authRepository.signOut()
        navController.replaceStack(
            with: AnyView(LandingView(router: self)),
            route: AdHocRoute(key: "landing")
        )
    }

    func finishOnboarding() {
        Task { @MainActor in
            await onboardingStore.markComplete()
            // The tab surfaces read entitlement synchronously from the
            // session - refresh it at the one choke point every entry into
            // home passes through (lapsed users enter too, degraded).
            container.membershipSession.status = await container.membershipStore.currentStatus()
            container.session.phase = .home
        }
    }
}
