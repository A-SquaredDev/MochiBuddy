//
//  AccountView.swift
//  MochiBuddy
//

import SwiftUI

struct AccountView: View {
    @State var viewModel: ObservableStateViewModel<
        AccountBehavior.UIState,
        AccountBehavior.ViewAction,
        AccountBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            progress: (index: 6, total: 8),
            onBack: { router.navigateBack() }
        ) {
            Halo(size: 190) {
                MochiPetView(vitality: 94, size: 140)
            }
            OnbHeading(
                eyebrow: "Almost there",
                title: "Let's keep \(viewModel.petName) safe",
                bodyText: "Create an account so your tasks, coins and \(viewModel.petName) follow you to any device, and nothing gets lost."
            )
        } footer: {
            if let detail = viewModel.signedInDetail {
                // Landing sign-in already linked this session - no re-auth.
                Text("Signed in as \(detail)")
                    .font(MochiFont.body(12.5, weight: .heavy))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                MochiButton(title: "Continue") {
                    viewModel.trigger(.continueTapped)
                }
            } else {
                SignInProviderButtons(
                    hashedNonce: viewModel.hashedNonce,
                    onAppleCompleted: { idToken, fullName in
                        viewModel.trigger(.appleCompleted(idToken: idToken, fullName: fullName))
                    },
                    onAppleFailed: { message in
                        viewModel.trigger(.appleFailed(message: message))
                    },
                    onGoogleTapped: {
                        viewModel.trigger(.googleTapped)
                    }
                )
                MochiTextLink(title: "Everything you set up is already saved.")
            }
        }
        .overlay {
            if viewModel.isWorking {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView().tint(theme.primary)
                }
            }
        }
        .alert(
            "Sign-in failed",
            isPresented: viewModel.collectBinding(for: \.errorMessage.isNotNil, action: .dismissError),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissError) } },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .alert(
            "Google sign-in isn't ready yet",
            isPresented: viewModel.collectBinding(for: \.showGoogleUnavailable, action: .dismissGoogleUnavailable),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissGoogleUnavailable) } },
            message: { Text("Use Continue with Apple for now. Google support is on the way.") }
        )
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToPaywall()
            case .skipToFinish:
                router.navigateToFinish()
            case .enterApp:
                router.finishOnboarding()
            case .showLapsedGate:
                router.navigateToLapsedGate()
            case .showRestoreFound(let purchase):
                router.navigateToRestoreFound(purchase)
            }
        }
    }
}

extension Optional where Wrapped == String {
    /// Enables alert bindings keyed off an optional message.
    var isNotNil: Bool { self != nil }
}
