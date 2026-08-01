//
//  RootView.swift
//  MochiBuddy
//
//  Owns the NavControllers + flow routers and switches between the
//  onboarding flow (splash-first for everyone) and the main tab shell.
//  Applies the active flavor to the whole tree.
//

import SwiftUI

struct RootView: View {
    let container: AppContainer

    @Environment(\.scenePhase) private var scenePhase
    @State private var navController = NavController()
    @State private var homeNavController = NavController()
    @State private var router: OnboardingRouter?
    @State private var homeRouter: HomeRouter?
    @State private var tasksRouter: TasksRouter?
    @State private var journalRouter: JournalRouter?
    @State private var youRouter: YouRouter?

    /// Entering home: refresh the entitlement snapshot (dev launches skip
    /// the flow's refresh), take provisional delivery as the permission
    /// floor for primer-skippers, land any widget completions, then lay
    /// the schedule.
    private func enteredHome() {
        Task { @MainActor in
            // Widget completions land first - ahead of the network round
            // trips below, so the drain the first Home refresh awaits
            // (coalesced in WidgetCompletionDrain) starts immediately.
            await container.widgetCompletionDrain.drain()
            container.membershipSession.status = await container.membershipStore.currentStatus()
            await container.notificationPermissionService.requestProvisionalIfUndetermined()
            // Pet identity loads (and one-time migrates legacy profiles,
            // incl. the interrupted-onboarding adoptedOn backstop) before
            // the lay so copy and action labels dress with the right name.
            if let userId = container.authRepository.currentAccount?.uid,
               let profile = try? await container.profileRepository.fetchProfile(userId: userId) {
                await container.petIdentityStore.load(profile: profile)
            }
            // Observation interval log backstop: stamp the log start once
            // and realign open vacation/lapse intervals with transitions
            // this device never witnessed (Feature 4).
            await container.observationIntervalRecorder.reconcile(
                isLapsed: container.membershipSession.isLapsed
            )
            // Letters (Feature 3): stamp this period's engagement marker
            // and compose the previous period if it earned one - a
            // USER-VISIBLE foreground path, which is what keeps the
            // dormancy marker truthful.
            await container.letterCompositionService.handleUserForeground()
            container.notificationOrchestrator.requestRelay(.appForeground)
        }
    }

    var body: some View {
        Group {
            switch container.session.phase {
            case .flow:
                if let router {
                    NavHost(controller: navController, root: router.start())
                } else {
                    container.themeStore.current.bg.ignoresSafeArea()
                }
            case .home:
                if let homeRouter, let tasksRouter, let journalRouter, let youRouter {
                    NavHost(
                        controller: homeNavController,
                        root: AnyView(MainTabView(
                            homeTab: homeRouter.start(),
                            tasksTab: tasksRouter.start(),
                            journalTab: journalRouter.start(),
                            youTab: youRouter.start(),
                            coordinator: container.tabCoordinator
                        ))
                    )
                } else {
                    container.themeStore.current.bg.ignoresSafeArea()
                }
            }
        }
        .environment(\.mochiTheme, container.themeStore.current)
        .preferredColorScheme(container.themeStore.current.isDark ? .dark : .light)
        .animation(MochiMotion.soft, value: container.session.phase == .home)
        .onLoad {
            router = OnboardingRouter(navController: navController, container: container)
            homeRouter = HomeRouter(container: container)
            tasksRouter = TasksRouter(navController: homeNavController, container: container)
            journalRouter = JournalRouter(navController: homeNavController, container: container)
            youRouter = YouRouter(navController: homeNavController, container: container)
            // Dev launches (-mochiStartAtHome) begin in home without the
            // phase change ever firing.
            if container.session.phase == .home {
                enteredHome()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The one guaranteed re-lay moment: predictions can only be
            // wrong in the direction where the app is open to fix them.
            // Widget completions land first so the lay sees them done.
            if phase == .active, container.session.phase == .home {
                Task { @MainActor in
                    await container.widgetCompletionDrain.drain()
                    // Entitlement can expire while backgrounded, and cold
                    // launch is the only other place that notices - without
                    // this a backgrounded app never meets the resubscribe
                    // gate. RevenueCat caches customerInfo, so rapid
                    // foregrounds stay cheap.
                    let wasLapsed = container.membershipSession.isLapsed
                    container.membershipSession.status = await container.membershipStore.currentStatus()
                    if !wasLapsed, container.membershipSession.isLapsed {
                        // Freshly lapsed: back through the flow - Splash
                        // re-evaluates and lands on the reactivate gate,
                        // the same path You's "Wake Mochi" takes. A user
                        // who already chose degraded mode stays put (the
                        // wasLapsed guard).
                        container.session.flowEntry = .splash
                        container.session.phase = .flow
                        return
                    }
                    // After the drain, so the composition barrier's flush
                    // sees widget completions already durable.
                    await container.letterCompositionService.handleUserForeground()
                    container.notificationOrchestrator.requestRelay(.appForeground)
                }
            }
        }
        .onChange(of: container.session.phase) { _, phase in
            // The stack a phase left behind must not greet its next visit.
            switch phase {
            case .flow: navController.popToRoot(animated: false)
            case .home:
                homeNavController.popToRoot(animated: false)
                enteredHome()
            }
        }
    }
}
