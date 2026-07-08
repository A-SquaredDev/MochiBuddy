//
//  DeleteConfirmView.swift
//  MochiBuddy
//

import SwiftUI
import AuthenticationServices

struct DeleteConfirmView: View {
    @State var viewModel: ObservableStateViewModel<
        DeleteConfirmBehavior.UIState,
        DeleteConfirmBehavior.ViewAction,
        DeleteConfirmBehavior.NavigationEvent
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Confirm deletion",
                    subtitle: "Last step",
                    onBack: { router.navigateBack() }
                )

                verifyCard

                if !viewModel.isVerified {
                    reauthControl
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("This is permanent")
                        .font(MochiFont.display(12.5, weight: .semibold))
                        .foregroundStyle(theme.danger)
                    Text("Tasks, lists, coins and streak are gone forever. Subscription access can be restored on a fresh install with \u{201C}Restore Purchases\u{201D} — your data cannot.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.danger.opacity(0.85))
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
                .background(theme.dangerSoft, in: RoundedRectangle(cornerRadius: 22))

                VStack(spacing: 9) {
                    DangerButton(
                        title: "Permanently delete everything",
                        isLoading: viewModel.isWorking,
                        filled: true
                    ) {
                        viewModel.trigger(.deleteTapped)
                    }
                    .disabled(!viewModel.isVerified)
                    .opacity(viewModel.isVerified ? 1 : 0.45)
                    MochiButton(title: "Keep my account", variant: .ghost) {
                        viewModel.trigger(.keepTapped)
                    }
                }
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .animation(MochiMotion.soft, value: viewModel.isVerified)
        .alert(
            "Verification failed",
            isPresented: viewModel.collectBinding(for: \.errorMessage.isNotNil, action: .dismissError),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissError) } },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .deleted: router.exitToOnboarding()
            case .close: router.exitDeleteFlow()
            }
        }
    }

    private var verifyCard: some View {
        MochiCard(padding: EdgeInsets(top: 16, leading: 15, bottom: 16, trailing: 15)) {
            VStack(spacing: 6) {
                Text(viewModel.isVerified ? "✅" : "🔐")
                    .font(.system(size: 34))
                Text(viewModel.isVerified ? "It's you" : "Verify it's you")
                    .font(MochiFont.display(16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(verifySub)
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var verifySub: String {
        if viewModel.isVerified {
            return "You can now permanently delete your account and its data."
        }
        return "For your security, sign in again before we permanently delete your account and its data."
    }

    @ViewBuilder
    private var reauthControl: some View {
        switch viewModel.method {
        case .apple:
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []
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
                    viewModel.trigger(.appleCompleted(idToken: idToken))
                case .failure:
                    // Treat as cancellation — no error surfaced.
                    viewModel.trigger(.appleFailed(message: ""))
                }
            }
            .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 8)

        case .google:
            Button {
                viewModel.trigger(.googleTapped)
            } label: {
                HStack(spacing: 9) {
                    Text("G")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x4285F4))
                    Text("Sign in with Google to confirm")
                        .font(MochiFont.display(15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x1F1F1F))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(viewModel.isWorking)

        case .none:
            EmptyView()
        }
    }
}
