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

        let session: AuthAccount?
        do {
            session = try await authRepository.currentSession()
        } catch {
            // The auth layer itself failed (distinct from "no session",
            // which is a normal fresh install). Proceeding used to mean a
            // sessionless flow whose onboarding writes silently vanished -
            // the Try again beat is finally reachable instead.
            await minimumBeat.value
            state.failedToStart = true
            return
        }

        guard let account = session else {
            // Fresh install or a post-sign-out relaunch: nothing exists
            // and nothing is minted here. The wizard's first step creates
            // the account for users who actually start; browsers and
            // sign-ins never leave one behind.
            await minimumBeat.value
            setNavigationEvent(.showLanding)
            return
        }

        await membershipStore.identify(userId: account.uid)
        try? await profileRepository.ensureProfile(for: account)
        let profile = try? await profileRepository.fetchProfile(userId: account.uid)
        await minimumBeat.value

        guard let profile, profile.onboardingComplete else {
            setNavigationEvent(.showLanding)
            return
        }

        switch await membershipStore.currentStatus() {
        case .active, .trial, .billingGrace:
            setNavigationEvent(.enterApp)
        case .lapsed, .notSubscribed:
            setNavigationEvent(.showWelcomeBack(summary(account: account, profile: profile)))
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
        return ReturningAccountSummary(
            name: name, detail: detail, providerLabel: provider, petName: profile.mochiName
        )
    }
}
