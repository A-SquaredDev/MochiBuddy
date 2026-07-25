//
//  SignInView.swift
//  MochiBuddy
//

import SwiftUI

struct SignInView: View {
    @State var viewModel: ObservableStateViewModel<
        SignInBehavior.UIState,
        SignInBehavior.ViewAction,
        SignInBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            onBack: { router.navigateBack() }
        ) {
            Halo(size: 190) {
                MochiPetView(vitality: 88, size: 140)
            }
            OnbHeading(
                eyebrow: "Welcome back",
                title: "Sign in to Mochi",
                bodyText: "Use the account you had before. Your tasks, coins and pet are right where you left them."
            )
        } footer: {
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
        .alert(
            "No account found",
            isPresented: viewModel.collectBinding(for: \.showNoAccountFound, action: .noAccountFoundConfirmed),
            actions: { Button("Set me up") { viewModel.trigger(.noAccountFoundConfirmed) } },
            message: { Text("That sign-in doesn't have a Mochi account yet. Let's set you up fresh.") }
        )
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .enterApp:
                router.finishOnboarding()
            case .showLapsedGate:
                router.navigateToLapsedGate()
            case .showRestoreFound(let purchase):
                router.navigateToRestoreFound(purchase)
            case .startOnboarding:
                router.navigateToMeetMochi()
            }
        }
    }
}
