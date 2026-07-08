//
//  DeleteWarnView.swift
//  MochiBuddy
//

import SwiftUI

struct DeleteWarnView: View {
    @State var viewModel: ObservableStateViewModel<
        DeleteWarnBehavior.UIState,
        DeleteWarnBehavior.ViewAction,
        DeleteWarnBehavior.NavigationEvent
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Delete account",
                    subtitle: "This can't be undone",
                    onBack: { router.navigateBack() }
                )

                MochiCard(padding: EdgeInsets(top: 16, leading: 15, bottom: 16, trailing: 15)) {
                    VStack(spacing: 4) {
                        MochiPetView(mood: .unwell, size: 104, squishOnTap: false)
                            .overlay(alignment: .bottomTrailing) {
                                Text("💔")
                                    .font(.system(size: 20))
                                    .offset(x: 4)
                            }
                        Text("We're sad to see you go")
                            .font(MochiFont.display(16, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text("Deleting your account permanently erases everything below. There's no way to bring it back.")
                            .font(MochiFont.body(12, weight: .bold))
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                MochiEyebrow(text: "What gets erased")
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    ForEach(viewModel.items) { item in
                        MochiListRow(
                            icon: item.icon,
                            iconBg: theme.dangerSoft,
                            title: item.title,
                            subtitle: item.subtitle,
                            onTap: nil,
                            right: { EmptyView() }
                        )
                    }
                }

                VStack(spacing: 9) {
                    DangerButton(title: "Continue to delete", isLoading: viewModel.isChecking, filled: false) {
                        viewModel.trigger(.continueTapped)
                    }
                    MochiButton(title: "Keep my account", variant: .ghost) {
                        viewModel.trigger(.keepTapped)
                    }
                }
                .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showSubscriptionWarning: router.navigateToDeleteSubscriptionWarning()
            case .showFinalConfirm: router.navigateToDeleteConfirm()
            case .close: router.exitDeleteFlow()
            }
        }
    }
}

/// Destructive pill — soft tint by default, solid danger when `filled`.
struct DangerButton: View {
    let title: String
    var isLoading = false
    var filled = false
    let action: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(filled ? .white : theme.danger)
                }
                Text(title)
                    .font(MochiFont.display(14, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? .white : theme.danger)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(filled ? theme.danger : theme.dangerSoft, in: Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
    }
}
