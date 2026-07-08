//
//  WelcomeBackView.swift
//  MochiBuddy
//

import SwiftUI

struct WelcomeBackView: View {
    @State var viewModel: ObservableStateViewModel<
        WelcomeBackBehavior.UIState,
        WelcomeBackBehavior.ViewAction,
        WelcomeBackBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold {
            Halo(size: 200) {
                MochiPetView(vitality: 40, size: 148)
            }
            OnbHeading(
                eyebrow: "Welcome back",
                title: "Mochi missed you",
                bodyText: "Everything's just as you left it. Let's pick up right where you stopped."
            )
            accountChip
                .padding(.horizontal, 2)
        } footer: {
            MochiButton(title: "Continue", isLoading: viewModel.isWorking) {
                viewModel.trigger(.continueTapped)
            }
            MochiTextLink(title: "Not you? Switch account") {
                viewModel.trigger(.switchAccountTapped)
            }
        }
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .enterApp:
                router.finishOnboarding()
            case .showLapsedGate:
                router.navigateToLapsedGate()
            case .showRestoreFound(let purchase):
                router.navigateToRestoreFound(purchase)
            case .restartOnboarding:
                router.restartOnboarding()
            }
        }
    }

    private var accountChip: some View {
        HStack(spacing: 11) {
            Text(viewModel.name.prefix(1).uppercased())
                .font(MochiFont.display(14, weight: .semibold))
                .foregroundStyle(theme.primaryInk)
                .frame(width: 34, height: 34)
                .background(theme.primary, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.name)
                    .font(MochiFont.display(13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(viewModel.detail)
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Text(viewModel.providerLabel)
                .font(MochiFont.body(10.5, weight: .heavy))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(theme.surface2, in: Capsule())
        .overlay(Capsule().stroke(theme.line, lineWidth: 1.5))
    }
}
