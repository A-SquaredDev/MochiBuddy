//
//  MainTabView.swift
//  MochiBuddy
//
//  The app shell after onboarding — Home · Tasks · You in a system TabView
//  (standard bar, SF Symbol icons, stays out of the keyboard's way). Tabs
//  stay mounted so scroll and view state survive switching, and each tab
//  fires onAppear when selected so its screen refreshes.
//

import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case tasks
    case you

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .tasks: "checklist"
        case .you: "person.crop.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .you: "You"
        }
    }
}

struct MainTabView: View {
    /// Tab roots, built by their routers (which own the ViewModel wiring).
    let homeTab: AnyView
    let tasksTab: AnyView
    let youTab: AnyView

    // "-mochiStartTab you" (a dev launch argument, read via UserDefaults'
    // argument-domain parsing) picks the initial tab for UI work.
    @State private var selected: MainTab =
        MainTab(rawValue: UserDefaults.standard.string(forKey: "mochiStartTab") ?? "") ?? .home
    @Environment(\.mochiTheme) private var theme

    var body: some View {
        TabView(selection: $selected) {
            Tab(MainTab.home.label, systemImage: MainTab.home.icon, value: .home) {
                homeTab
            }
            Tab(MainTab.tasks.label, systemImage: MainTab.tasks.icon, value: .tasks) {
                tasksTab
            }
            Tab(MainTab.you.label, systemImage: MainTab.you.icon, value: .you) {
                youTab
            }
        }
        .tint(theme.primaryText)
        .background(theme.bg.ignoresSafeArea())
    }
}
