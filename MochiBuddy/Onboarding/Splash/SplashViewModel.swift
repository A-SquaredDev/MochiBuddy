//
//  SplashViewModel.swift
//  MochiBuddy
//
//  Branded launch beat. Creates the anonymous auth session (so onboarding
//  choices save immediately) and routes: new users into Meet Mochi,
//  returning users to home or the re-entry flows.
//

import Foundation

final class SplashViewModel: ObservableStateViewModel<
    SplashBehavior.UIState,
    SplashBehavior.ViewAction,
    SplashBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let membershipStore: MembershipStore

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        membershipStore: MembershipStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.membershipStore = membershipStore
        super.init(initialState: SplashBehavior.UIState())
    }

    override func triggerAsync(_ action: SplashBehavior.ViewAction) async {
        switch action {
        case .load, .retryTapped:
            state.failedToStart = false
            await start()
        }
    }

    private func start() async {
        // Keep the brand beat visible even when everything resolves instantly.
        let minimumBeat = Task { try? await Task.sleep(for: .seconds(1.1)) }

        do {
            let account = try await authRepository.ensureSession()
            await membershipStore.identify(userId: account.uid)
            try? await profileRepository.ensureProfile(for: account)
            let profile = try? await profileRepository.fetchProfile(userId: account.uid)
            await minimumBeat.value

            guard let profile, profile.onboardingComplete else {
                setNavigationEvent(.showMeetMochi)
                return
            }

            switch await membershipStore.currentStatus() {
            case .active, .trial:
                setNavigationEvent(.enterApp)
            case .lapsed, .notSubscribed:
                setNavigationEvent(.showWelcomeBack(summary(account: account, profile: profile)))
            }
        } catch {
            // Offline or Firebase unreachable — never trap the user on splash.
            await minimumBeat.value
            setNavigationEvent(.showMeetMochi)
        }
    }

    private func summary(account: AuthAccount, profile: UserProfile) -> ReturningAccountSummary {
        let name = profile.displayName ?? account.displayName ?? "Friend"
        let detail = account.email ?? "Signed in"
        let provider: String = switch account.providerId {
        case "apple.com": "Apple ID"
        case "google.com": "Google"
        default: "Account"
        }
        return ReturningAccountSummary(name: name, detail: detail, providerLabel: provider)
    }
}
