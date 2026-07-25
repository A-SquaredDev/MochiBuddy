//
//  SignInViewModel.swift
//  MochiBuddy
//
//  Direct sign-in from the landing screen. A recognised account routes
//  on its membership (home, restore, or the expired gate); a provider
//  account with no Mochi profile falls back to fresh onboarding.
//

import Foundation

final class SignInViewModel: ObservableStateViewModel<
    SignInBehavior.UIState,
    SignInBehavior.ViewAction,
    SignInBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let membershipStore: MembershipStore

    private var pendingNonce: AppleSignInNonce?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        membershipStore: MembershipStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.membershipStore = membershipStore
        super.init(initialState: SignInBehavior.UIState())
    }

    override func triggerAsync(_ action: SignInBehavior.ViewAction) async {
        switch action {
        case .load:
            prepareNonce()

        case .appleCompleted(let idToken, let fullName):
            guard let nonce = pendingNonce else {
                state.errorMessage = "Something went wrong. Please try again."
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
                await routeAfterSignIn(account)
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't sign in with Apple. \(error.localizedDescription)"
                prepareNonce()
            }

        case .appleFailed(let message):
            // User-cancelled flows arrive here too - only surface real failures.
            if !message.isEmpty {
                state.errorMessage = message
            }
            prepareNonce()

        case .googleTapped:
            state.isWorking = true
            do {
                let account = try await authRepository.signInWithGoogle()
                await routeAfterSignIn(account)
            } catch AuthRepositoryError.cancelled {
                state.isWorking = false
            } catch AuthRepositoryError.providerUnavailable {
                state.isWorking = false
                state.showGoogleUnavailable = true
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't sign in with Google. \(error.localizedDescription)"
            }

        case .noAccountFoundConfirmed:
            // Fires from both the button and the alert-dismiss binding -
            // only the first one may navigate.
            guard uiState.showNoAccountFound else { return }
            state.showNoAccountFound = false
            setNavigationEvent(.startOnboarding)

        case .dismissError:
            state.errorMessage = nil

        case .dismissGoogleUnavailable:
            state.showGoogleUnavailable = false
        }
    }

    private func routeAfterSignIn(_ account: AuthAccount) async {
        // Sign-in can land on a different uid (existing account) -
        // re-point purchases at whoever we actually are now.
        await membershipStore.identify(userId: account.uid)
        let destination = await PostSignIn.resolve(
            account: account,
            profileRepository: profileRepository,
            membershipStore: membershipStore
        )
        state.isWorking = false
        switch destination {
        case .enterApp:
            setNavigationEvent(.enterApp)
        case .lapsedGate:
            setNavigationEvent(.showLapsedGate)
        case .restoreFound(let purchase):
            setNavigationEvent(.showRestoreFound(purchase))
        case .continueOnboarding, .skipToFinish:
            // No completed profile behind this provider - the wizard is
            // still the right path (the Account step will recognise the
            // session and skip re-linking).
            state.showNoAccountFound = true
        }
    }

    private func prepareNonce() {
        let nonce = authRepository.makeAppleNonce()
        pendingNonce = nonce
        state.hashedNonce = nonce.sha256
    }
}
