//
//  MainTabView.swift
//  MochiBuddy
//
//  The app shell after onboarding - Home · Tasks · You in a system TabView
//  (standard bar, SF Symbol icons, stays out of the keyboard's way). Tabs
//  stay mounted so scroll and view state survive switching, and each tab
//  fires onAppear when selected so its screen refreshes.
//

import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case tasks
    case journal
    case you

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .tasks: "checklist"
        // DESIGN NOTE: SF Symbol book stands in until commissioned tab
        // art lands (roadmap #6). The label stays the static word
        // "Journal" - tab bars never carry user content (Feature 1's
        // compact-surface rule).
        case .journal: "book.fill"
        case .you: "person.crop.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .journal: "Journal"
        case .you: "You"
        }
    }
}

struct MainTabView: View {
    /// Tab roots, built by their routers (which own the ViewModel wiring).
    let homeTab: AnyView
    let tasksTab: AnyView
    let journalTab: AnyView
    let youTab: AnyView
    /// Selection lives on the coordinator so the Home envelope and letter
    /// notifications can route into the Journal programmatically.
    @Bindable var coordinator: TabCoordinator

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        TabView(selection: $coordinator.selected) {
            Tab(MainTab.home.label, systemImage: MainTab.home.icon, value: .home) {
                homeTab
            }
            Tab(MainTab.tasks.label, systemImage: MainTab.tasks.icon, value: .tasks) {
                tasksTab
            }
            Tab(MainTab.journal.label, systemImage: MainTab.journal.icon, value: .journal) {
                journalTab
            }
            Tab(MainTab.you.label, systemImage: MainTab.you.icon, value: .you) {
                youTab
            }
        }
        .tint(theme.primaryText)
        .background(theme.bg.ignoresSafeArea())
    }
}
