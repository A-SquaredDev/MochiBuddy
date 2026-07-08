//
//  AccountViewModel.swift
//  MochiBuddy
//
//  8 · Continue with Apple / Google — placed after the value moment.
//  Links the credential onto the anonymous session so nothing is lost.
//

import Foundation

final class AccountViewModel: ObservableStateViewModel<
    AccountBehavior.UIState,
    AccountBehavior.ViewAction,
    AccountBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let onboardingStore: OnboardingStore
    private let membershipStore: MembershipStore

    private var pendingNonce: AppleSignInNonce?

    init(authRepository: AuthRepository, onboardingStore: OnboardingStore, membershipStore: MembershipStore) {
        self.authRepository = authRepository
        self.onboardingStore = onboardingStore
        self.membershipStore = membershipStore
        super.init(initialState: AccountBehavior.UIState())
    }

    override func triggerAsync(_ action: AccountBehavior.ViewAction) async {
        switch action {
        case .load:
            prepareNonce()

        case .appleCompleted(let idToken, let fullName):
            guard let nonce = pendingNonce else {
                state.errorMessage = "Something went wrong — please try again."
                prepareNonce()
                return
            }
            state.isWorking = true
            do {
                let account = try await authRepository.completeAppleSignIn(
                    idToken: idToken,
                    rawNonce: nonce.raw,
                    fullName: fullName
                )
                // Sign-in can land on a different uid (existing account) —
                // re-point purchases at whoever we actually are now.
                await membershipStore.identify(userId: account.uid)
                await onboardingStore.recordAccountLink(account)
                state.isWorking = false
                setNavigationEvent(.next)
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't sign in with Apple. \(error.localizedDescription)"
                prepareNonce()
            }

        case .appleFailed(let message):
            // User-cancelled flows arrive here too — only surface real failures.
            if !message.isEmpty {
                state.errorMessage = message
            }
            prepareNonce()

        case .googleTapped:
            state.isWorking = true
            do {
                let account = try await authRepository.signInWithGoogle()
                await membershipStore.identify(userId: account.uid)
                await onboardingStore.recordAccountLink(account)
                state.isWorking = false
                setNavigationEvent(.next)
            } catch AuthRepositoryError.cancelled {
                state.isWorking = false
            } catch AuthRepositoryError.providerUnavailable {
                state.isWorking = false
                state.showGoogleUnavailable = true
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't sign in with Google. \(error.localizedDescription)"
            }

        case .dismissError:
            state.errorMessage = nil

        case .dismissGoogleUnavailable:
            state.showGoogleUnavailable = false
        }
    }

    private func prepareNonce() {
        let nonce = authRepository.makeAppleNonce()
        pendingNonce = nonce
        state.hashedNonce = nonce.sha256
    }
}
