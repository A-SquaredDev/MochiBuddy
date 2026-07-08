//
//  AccountView.swift
//  MochiBuddy
//

import SwiftUI
import AuthenticationServices

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
                title: "Let's keep your Mochi safe",
                bodyText: "Create an account so your tasks, coins and Mochi's mood follow you to any device — and nothing gets lost."
            )
        } footer: {
            appleButton
            googleButton
            MochiTextLink(title: "Everything you set up is already saved.")
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
            message: { Text("Use Continue with Apple for now — Google support is on the way.") }
        )
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToPaywall()
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = viewModel.hashedNonce
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    viewModel.trigger(.appleFailed(message: "Apple didn't return a valid credential."))
                    return
                }
                viewModel.trigger(.appleCompleted(idToken: idToken, fullName: credential.fullName))
            case .failure:
                // Treat as cancellation — no error surfaced.
                viewModel.trigger(.appleFailed(message: ""))
            }
        }
        .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
        .frame(height: 50)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
    }

    private var googleButton: some View {
        Button {
            viewModel.trigger(.googleTapped)
        } label: {
            HStack(spacing: 9) {
                Text("G")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x4285F4))
                Text("Continue with Google")
                    .font(MochiFont.display(15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x1F1F1F))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
        }
        .buttonStyle(SquishButtonStyle())
    }
}

extension Optional where Wrapped == String {
    /// Enables alert bindings keyed off an optional message.
    var isNotNil: Bool { self != nil }
}
