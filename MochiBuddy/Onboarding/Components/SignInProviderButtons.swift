//
//  SignInProviderButtons.swift
//  MochiBuddy
//
//  The Apple + Google sign-in pair, shared by the onboarding Account
//  step and the landing sign-in screen.
//

import SwiftUI
import AuthenticationServices

struct SignInProviderButtons: View {
    /// SHA-256 nonce the Sign in with Apple request must carry.
    let hashedNonce: String?
    let onAppleCompleted: (_ idToken: String, _ fullName: PersonNameComponents?) -> Void
    /// Empty message means user cancellation - surface nothing.
    let onAppleFailed: (_ message: String) -> Void
    let onGoogleTapped: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        appleButton
        googleButton
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    onAppleFailed("Apple didn't return a valid credential.")
                    return
                }
                onAppleCompleted(idToken, credential.fullName)
            case .failure:
                // Treat as cancellation - no error surfaced.
                onAppleFailed("")
            }
        }
        .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
        .frame(height: 50)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
    }

    private var googleButton: some View {
        Button {
            onGoogleTapped()
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
