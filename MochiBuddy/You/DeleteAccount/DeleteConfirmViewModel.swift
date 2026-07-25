//
//  DeleteConfirmViewModel.swift
//  MochiBuddy
//
//  Delete account · 3 - reauthenticate (Firebase requires a recent login),
//  then erase: Firestore subtree first (rules lock it once the user is
//  gone), then the Auth user. Guest accounts skip straight to the button.
//

import Foundation

final class DeleteConfirmViewModel: ObservableStateViewModel<
    DeleteConfirmBehavior.UIState,
    DeleteConfirmBehavior.ViewAction,
    DeleteConfirmBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let accountEraser: AccountEraser
    private let observationLedger: ObservationLedger?
    private let callbackLedger: CallbackLedger?
    private let suggestionLedger: SuggestionLedger?

    private var pendingNonce: AppleSignInNonce?

    init(
        authRepository: AuthRepository,
        accountEraser: AccountEraser,
        observationLedger: ObservationLedger? = nil,
        callbackLedger: CallbackLedger? = nil,
        suggestionLedger: SuggestionLedger? = nil
    ) {
        self.authRepository = authRepository
        self.accountEraser = accountEraser
        self.observationLedger = observationLedger
        self.callbackLedger = callbackLedger
        self.suggestionLedger = suggestionLedger
        super.init(initialState: DeleteConfirmBehavior.UIState())
    }

    override func triggerAsync(_ action: DeleteConfirmBehavior.ViewAction) async {
        switch action {
        case .load:
            let account = authRepository.currentAccount
            switch account?.providerId {
            case "apple.com":
                state.method = .apple
                prepareNonce()
            case "google.com":
                state.method = .google
            default:
                // Anonymous/guest - recent anonymous sign-in needs no reauth.
                state.method = .none
                state.isVerified = true
            }

        case .appleCompleted(let idToken):
            guard let nonce = pendingNonce else {
                state.errorMessage = "Something went wrong. Please try again."
                prepareNonce()
                return
            }
            state.isWorking = true
            do {
                try await authRepository.reauthenticateWithApple(idToken: idToken, rawNonce: nonce.raw)
                state.isWorking = false
                state.isVerified = true
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't verify it's you. \(error.localizedDescription)"
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
                try await authRepository.reauthenticateWithGoogle()
                state.isWorking = false
                state.isVerified = true
            } catch AuthRepositoryError.cancelled {
                state.isWorking = false
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't verify it's you. \(error.localizedDescription)"
            }

        case .deleteTapped:
            guard uiState.isVerified, let userId = authRepository.currentAccount?.uid else { return }
            state.isWorking = true
            do {
                try await accountEraser.eraseAllData(userId: userId)
                // Deletion clears the UID's observation + callback +
                // suggestion cadence (Feature 4 + 2 + 5 ledger hygiene) -
                // device-local, so it rides the erase, not the Firestore
                // subtree.
                observationLedger?.clear(userId: userId)
                callbackLedger?.clear(userId: userId)
                suggestionLedger?.clear(userId: userId)
                try await authRepository.deleteCurrentUser()
                state.isWorking = false
                setNavigationEvent(.deleted)
            } catch {
                state.isWorking = false
                state.errorMessage = "Couldn't delete your account. Check your connection and try again. (\(error.localizedDescription))"
            }

        case .keepTapped:
            setNavigationEvent(.close)

        case .dismissError:
            state.errorMessage = nil
        }
    }

    private func prepareNonce() {
        let nonce = authRepository.makeAppleNonce()
        pendingNonce = nonce
        state.hashedNonce = nonce.sha256
    }
}
