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

    @State private var navController = NavController()
    @State private var homeNavController = NavController()
    @State private var router: OnboardingRouter?
    @State private var homeRouter: HomeRouter?
    @State private var tasksRouter: TasksRouter?
    @State private var youRouter: YouRouter?

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
                if let homeRouter, let tasksRouter, let youRouter {
                    NavHost(
                        controller: homeNavController,
                        root: AnyView(MainTabView(
                            homeTab: homeRouter.start(),
                            tasksTab: tasksRouter.start(),
                            youTab: youRouter.start()
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
            youRouter = YouRouter(navController: homeNavController, container: container)
        }
        .onChange(of: container.session.phase) { _, phase in
            // The stack a phase left behind must not greet its next visit.
            switch phase {
            case .flow: navController.popToRoot(animated: false)
            case .home: homeNavController.popToRoot(animated: false)
            }
        }
    }
}
