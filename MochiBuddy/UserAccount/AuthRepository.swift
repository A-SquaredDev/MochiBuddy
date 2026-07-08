//
//  AuthRepository.swift
//  MochiBuddy
//
//  Abstracts Firebase Auth. Anonymous-first: a session is created at splash
//  so onboarding choices save immediately; Continue-with-Apple/Google links
//  the credential onto the anonymous account so nothing is lost.
//

import Foundation
import UIKit
import CryptoKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

struct AuthAccount: Equatable {
    let uid: String
    let isAnonymous: Bool
    let displayName: String?
    let email: String?
    let providerId: String?
}

struct AppleSignInNonce {
    let raw: String
    let sha256: String
}

enum AuthRepositoryError: Error {
    case noActiveSession
    /// The provider needs an SDK/config not present yet.
    case providerUnavailable(String)
    case invalidCredential
    /// The user dismissed the provider's sign-in sheet — not an error to surface.
    case cancelled
}

protocol AuthRepository: AnyObject {
    var currentAccount: AuthAccount? { get }
    /// Signs in anonymously when no valid session exists; recovers when the
    /// cached session points at a user deleted server-side.
    @discardableResult
    func ensureSession() async throws -> AuthAccount
    func makeAppleNonce() -> AppleSignInNonce
    /// Links the Apple credential to the current (anonymous) user. If the
    /// credential already belongs to an existing account, signs into it instead.
    func completeAppleSignIn(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthAccount
    func signInWithGoogle() async throws -> AuthAccount
    /// Signs out the current user ("Not you? Switch account").
    func signOut() throws
}

final class FirebaseAuthRepository: AuthRepository {

    var currentAccount: AuthAccount? {
        Auth.auth().currentUser.map(Self.account(from:))
    }

    @discardableResult
    func ensureSession() async throws -> AuthAccount {
        if let user = Auth.auth().currentUser {
            do {
                try await user.reload()
                return Self.account(from: user)
            } catch where Self.isStaleSessionError(error) {
                // The keychain session outlived the server-side user (e.g.
                // the account was deleted in the Firebase console). Start over.
                try? Auth.auth().signOut()
            } catch {
                // Offline or transient — keep the cached session.
                return Self.account(from: user)
            }
        }
        let result = try await Auth.auth().signInAnonymously()
        return Self.account(from: result.user)
    }

    func makeAppleNonce() -> AppleSignInNonce {
        let raw = Self.randomNonceString()
        let hashed = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return AppleSignInNonce(raw: raw, sha256: hashed)
    }

    func completeAppleSignIn(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthAccount {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        let name = fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
        return try await signInOrLink(with: credential, pendingDisplayName: name)
    }

    func signInWithGoogle() async throws -> AuthAccount {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthRepositoryError.providerUnavailable("Google")
        }
        guard let presenter = Self.presentingViewController() else {
            throw AuthRepositoryError.providerUnavailable("Google")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            throw AuthRepositoryError.cancelled
        }

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthRepositoryError.invalidCredential
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        return try await signInOrLink(with: credential, pendingDisplayName: result.user.profile?.name)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Shared link-or-sign-in flow

    private func signInOrLink(with credential: AuthCredential, pendingDisplayName: String?) async throws -> AuthAccount {
        if let user = Auth.auth().currentUser {
            if await Self.isSessionAlive(user) {
                do {
                    let result = try await user.link(with: credential)
                    await Self.applyDisplayNameIfMissing(pendingDisplayName, to: result.user)
                    return Self.account(from: result.user)
                } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                    // The provider account already has a Mochi account — sign into it.
                    let existing = (error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential) ?? credential
                    let result = try await Auth.auth().signIn(with: existing)
                    return Self.account(from: result.user)
                } catch let error as NSError where error.code == AuthErrorCode.providerAlreadyLinked.rawValue {
                    // Retry after a partial success — the user is already linked.
                    return Self.account(from: user)
                }
            } else {
                // Stale keychain session (user deleted server-side) — drop it
                // and sign in fresh with the provider credential.
                try? Auth.auth().signOut()
            }
        }
        let result = try await Auth.auth().signIn(with: credential)
        await Self.applyDisplayNameIfMissing(pendingDisplayName, to: result.user)
        return Self.account(from: result.user)
    }

    private static func isSessionAlive(_ user: User) async -> Bool {
        do {
            try await user.reload()
            return true
        } catch where isStaleSessionError(error) {
            return false
        } catch {
            return true
        }
    }

    private static func isStaleSessionError(_ error: Error) -> Bool {
        let code = (error as NSError).code
        return code == AuthErrorCode.userNotFound.rawValue
            || code == AuthErrorCode.userTokenExpired.rawValue
            || code == AuthErrorCode.invalidUserToken.rawValue
            || code == AuthErrorCode.userDisabled.rawValue
    }

    private static func applyDisplayNameIfMissing(_ name: String?, to user: User) async {
        guard user.displayName == nil, let name, !name.isEmpty else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = name
        try? await change.commitChanges()
    }

    private static func account(from user: User) -> AuthAccount {
        AuthAccount(
            uid: user.uid,
            isAnonymous: user.isAnonymous,
            displayName: user.displayName,
            email: user.email,
            providerId: user.providerData.first?.providerID
        )
    }

    private static func presentingViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            if Int(random) < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }
}
