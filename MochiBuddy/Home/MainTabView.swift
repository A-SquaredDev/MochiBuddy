//
//  MainTabView.swift
//  MochiBuddy
//
//  The app shell after onboarding — Home · Tasks · You behind a custom
//  bottom nav (design shell BottomNav). Tabs stay mounted so scroll and
//  view state survive switching; pushed screens cover the bar via NavHost.
//

import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case tasks
    case you

    var icon: String {
        switch self {
        case .home: "🍡"
        case .tasks: "🗒️"
        case .you: "⚙️"
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
        VStack(spacing: 0) {
            ZStack {
                tab(homeTab, .home)
                tab(tasksTab, .tasks)
                tab(youTab, .you)
            }
            MochiTabBar(selected: $selected)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    /// Keeps every tab in the hierarchy (state survives switching) while
    /// only the selected one is visible and hittable.
    private func tab(_ content: some View, _ tab: MainTab) -> some View {
        content
            .opacity(selected == tab ? 1 : 0)
            .allowsHitTesting(selected == tab)
            .accessibilityHidden(selected != tab)
    }
}

struct MochiTabBar: View {
    @Binding var selected: MainTab

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isOn = tab == selected
                Button {
                    guard !isOn else { return }
                    Haptics.selection()
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        Text(tab.icon)
                            .font(.system(size: 18))
                            .grayscale(isOn ? 0 : 0.4)
                            .opacity(isOn ? 1 : 0.85)
                        Text(tab.label)
                            .font(MochiFont.display(11, weight: .medium))
                            .foregroundStyle(isOn ? theme.primaryText : theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .background(theme.surface)
        .overlay(alignment: .top) {
            theme.line.frame(height: 1)
        }
    }
}
