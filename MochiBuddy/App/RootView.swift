//
//  RootView.swift
//  MochiBuddy
//
//  Owns the NavController + OnboardingRouter and switches between the
//  flow (splash-first for everyone) and home. Applies the active flavor
//  to the whole tree.
//

import SwiftUI

struct RootView: View {
    let container: AppContainer

    @State private var navController = NavController()
    @State private var router: OnboardingRouter?

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
                HomePlaceholderView()
            }
        }
        .environment(\.mochiTheme, container.themeStore.current)
        .preferredColorScheme(container.themeStore.current.isDark ? .dark : .light)
        .animation(MochiMotion.soft, value: container.session.phase == .home)
        .onLoad {
            router = OnboardingRouter(navController: navController, container: container)
        }
    }
}
