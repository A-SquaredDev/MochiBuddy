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
    /// When the foreground pipeline last ran in full. A quick bounce to
    /// another app (share sheet, notification detour, app switcher) used
    /// to re-run the whole pipeline - warm-up queries, letters, relay -
    /// for a world that cannot meaningfully have changed in seconds.
    @State private var lastForegroundPipelineAt: Date?
    /// Under this, a re-activation skips the pipeline unless the drain
    /// landed widget completions (those must become visible immediately).
    /// 90s is well under a letter period, so the engagement marker's
    /// per-period truthfulness is unaffected.
    private static let foregroundCooldown: TimeInterval = 90

    /// Set when entering Home finds an account with no display name -
    /// Apple hands one over on the first authorization only, so a fresh
    /// profile behind a re-signed-in Apple account has nothing to greet.
    @State private var namePrompt: NamePromptRequest?

    private struct NamePromptRequest: Identifiable {
        /// The signed-in uid, which is also what makes the sheet identity.
        let id: String
        let petName: String
    }

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
            // Counts as a pipeline run: the scenePhase activation that
            // lands right after a dev launch (or onboarding exit) would
            // otherwise run the whole thing a second time.
            lastForegroundPipelineAt = .now
            // Widget completions land first - ahead of the network round
            // trips below, so the drain the first Home refresh awaits
            // (coalesced in WidgetCompletionDrain) starts immediately.
            await container.widgetCompletionDrain.drain()
            container.membershipSession.status = await container.membershipStore.currentStatus()
            await container.notificationPermissionService.requestProvisionalIfUndetermined()
            // Pet identity loads (and one-time migrates legacy profiles,
            // incl. the interrupted-onboarding adoptedOn backstop) before
            // the lay so copy and action labels dress with the right name.
            if let userId = container.authRepository.currentAccount?.uid {
                let profile = try? await container.profileRepository.fetchProfile(userId: userId)
                if let profile {
                    await container.petIdentityStore.load(profile: profile)
                }
                // After the pet identity loads, so the ask can use the
                // pet's real name.
                if container.displayNamePromptGate.shouldPrompt(profile: profile, userId: userId) {
                    namePrompt = NamePromptRequest(
                        id: userId,
                        petName: container.petIdentityStore.name
                    )
                }
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
        .sheet(item: $namePrompt) { request in
            DisplayNamePromptView(
                viewModel: DisplayNamePromptViewModel(
                    userId: request.id,
                    petName: request.petName,
                    profileRepository: container.profileRepository,
                    gate: container.displayNamePromptGate
                ),
                onDismiss: { namePrompt = nil }
            )
            .environment(\.mochiTheme, container.themeStore.current)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
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
                    let drained = await container.widgetCompletionDrain.drain()
                    // Cool-down: a re-activation moments after the last
                    // full pipeline changes nothing worth 4 queries - the
                    // caches are still warm and the schedule still laid.
                    // A non-empty drain overrides it: those completions
                    // must reach the relay and the tabs right now.
                    if drained == 0, let last = lastForegroundPipelineAt,
                       Date.now.timeIntervalSince(last) < Self.foregroundCooldown {
                        return
                    }
                    lastForegroundPipelineAt = .now
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
                    // The ONE real data refresh per foreground: the task
                    // cache re-fetches, then the tabs re-derive from warm
                    // caches via the pulse below (their own scenePhase
                    // refreshes are gone - three overlapping pipelines
                    // used to re-read the same collections).
                    if let userId = container.authRepository.currentAccount?.uid {
                        await container.cachingTaskRepository.refresh(userId: userId)
                    }
                    // After the drain, so the composition barrier's flush
                    // sees widget completions already durable.
                    await container.letterCompositionService.handleUserForeground()
                    container.notificationOrchestrator.requestRelay(.appForeground)
                    container.tabCoordinator.pulseForeground()
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
