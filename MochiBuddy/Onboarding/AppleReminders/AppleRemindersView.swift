//
//  AppleRemindersView.swift
//  MochiBuddy
//

import SwiftUI

struct AppleRemindersView: View {
    @State var viewModel: ObservableStateViewModel<
        AppleRemindersBehavior.UIState,
        AppleRemindersBehavior.ViewAction,
        AppleRemindersBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            progress: (index: 5, total: 8),
            onBack: { router.navigateBack() },
            skipTitle: "Skip",
            onSkip: { viewModel.trigger(.skipTapped) },
            centered: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                OnbHeading(
                    eyebrow: "Optional",
                    title: "Already use Apple Reminders?",
                    bodyText: "Choose which lists to bring in, so Mochi keeps an eye on everything in one place. We'll never touch your grocery list unless you want us to.",
                    align: .leading
                )
                .padding(.top, 8)

                if viewModel.phase == .picking {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.lists) { list in
                                ReminderListRow(item: list) {
                                    viewModel.trigger(.toggleList(list.id))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                } else {
                    primerIllustration
                }

                Label {
                    Text("iPhone only · you can change this later in Settings.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(MochiFont.body(11, weight: .bold))
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 4)
            }
        } footer: {
            MochiButton(title: viewModel.ctaTitle, isLoading: viewModel.isWorking) {
                viewModel.trigger(.primaryTapped)
            }
        }
        .animation(MochiMotion.soft, value: viewModel.phase)
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToAccount()
            }
        }
    }

    /// Placeholder rows shown before access is granted.
    private var primerIllustration: some View {
        VStack(spacing: 8) {
            ForEach(["Work", "Personal", "Groceries"], id: \.self) { name in
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(MochiFont.body(13, weight: .heavy))
                            .foregroundStyle(theme.ink)
                        Text("· · ·")
                            .font(MochiFont.body(11, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.muted)
                }
                .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
                .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: MochiRadius.md)
                        .stroke(theme.line, lineWidth: 1.5)
                )
            }
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }
}

private struct ReminderListRow: View {
    let item: AppleRemindersBehavior.ListUIItem
    let onToggle: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(MochiFont.body(13, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Text(item.countText)
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            MochiToggle(isOn: Binding(get: { item.isOn }, set: { _ in onToggle() }))
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, lineWidth: 1.5)
        )
    }
}
