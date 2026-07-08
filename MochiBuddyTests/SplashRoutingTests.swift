//
//  SplashRoutingTests.swift
//  MochiBuddyTests
//
//  Splash is the reinstall gauntlet: the Firebase keychain session survives
//  app deletion, so a fresh install can wake up as ANY of these people —
//  brand new, mid-onboarding, subscribed, or lapsed. Every branch must land
//  somewhere sane, and offline must never trap anyone on the splash screen.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeSplashVM(
    auth: StubAuthRepository = StubAuthRepository(),
    profile: UserProfile? = makeProfile(),
    fetchError: Error? = nil,
    membership: StubMembershipStore = StubMembershipStore()
) -> (SplashViewModel, StubAuthRepository, StubProfileRepository, StubMembershipStore) {
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    profileRepo.fetchError = fetchError
    let vm = SplashViewModel(
        authRepository: auth,
        profileRepository: profileRepo,
        membershipStore: membership
    )
    return (vm, auth, profileRepo, membership)
}

@MainActor
private func completedProfile(name: String? = "Alex Rivera") -> UserProfile {
    var profile = makeProfile()
    profile.displayName = name
    profile.onboardingComplete = true
    return profile
}

@Suite("Splash · routing")
@MainActor
struct SplashRoutingTests {

    @Test("a brand-new install goes to Meet Mochi")
    func freshInstall() async {
        // ensureProfile creates the doc; fetch returns a blank profile.
        var blank = makeProfile()
        blank.onboardingComplete = false
        let (vm, _, _, _) = makeSplashVM(profile: blank)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.showMeetMochi])
    }

    @Test("reinstall with a live subscription goes straight home — no onboarding replay")
    func reinstallSubscribed() async {
        let membership = StubMembershipStore()
        membership.status = .active(plan: .yearly, renewsAt: nil)
        let (vm, _, _, _) = makeSplashVM(profile: completedProfile(), membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.enterApp])
    }

    @Test("a trial user is treated as subscribed")
    func trialEntersApp() async {
        let membership = StubMembershipStore()
        membership.status = .trial(endsAt: Date.now.addingTimeInterval(3 * 24 * 3600))
        let (vm, _, _, _) = makeSplashVM(profile: completedProfile(), membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.enterApp])
    }

    @Test("reinstall with a lapsed membership lands on Welcome Back with the right identity")
    func reinstallLapsed() async {
        let membership = StubMembershipStore()
        membership.status = .lapsed
        let (vm, _, _, _) = makeSplashVM(profile: completedProfile(), membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()

        guard case .showWelcomeBack(let summary) = recorder.events.first else {
            Issue.record("expected welcome back, got \(recorder.events)")
            return
        }
        #expect(summary.name == "Alex Rivera")
        #expect(summary.detail == "alex@hey.com")
        #expect(summary.providerLabel == "Apple ID")
    }

    @Test("finished onboarding but never subscribed → Welcome Back (the paywall gate), not home")
    func neverSubscribed() async {
        let (vm, _, _, _) = makeSplashVM(profile: completedProfile())
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        guard case .showWelcomeBack = recorder.events.first else {
            Issue.record("an unsubscribed account must never slip into the app, got \(recorder.events)")
            return
        }
    }

    @Test("unfinished onboarding replays onboarding even for a recognised account")
    func unfinishedOnboardingReplays() async {
        var profile = completedProfile()
        profile.onboardingComplete = false
        let (vm, _, _, _) = makeSplashVM(profile: profile)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.showMeetMochi])
    }

    @Test("purchases are re-pointed at the session's uid before anything else routes")
    func identifiesMembership() async {
        let (vm, _, _, membership) = makeSplashVM(profile: completedProfile())
        await vm.triggerAsync(.load)
        #expect(membership.identifiedUserIds == ["user1"])
    }

    @Test("the profile doc is (re)ensured for the signed-in account on every launch")
    func ensuresProfile() async {
        let (vm, _, profileRepo, _) = makeSplashVM(profile: completedProfile())
        await vm.triggerAsync(.load)
        #expect(profileRepo.ensuredAccounts.map(\.uid) == ["user1"])
    }

    // MARK: Failure paths — never trap anyone on splash

    @Test("auth completely unavailable still lands on Meet Mochi")
    func authFailureFallsBack() async {
        let auth = StubAuthRepository()
        auth.ensureSessionError = TestError()
        let (vm, _, _, _) = makeSplashVM(auth: auth)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.showMeetMochi])
    }

    @Test("a profile fetch failure (offline) falls back to Meet Mochi instead of hanging")
    func profileFetchFailureFallsBack() async {
        let (vm, _, _, _) = makeSplashVM(fetchError: TestError())
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.showMeetMochi])
    }

    @Test("a missing profile document routes like a fresh user")
    func missingProfileDocument() async {
        let (vm, _, _, _) = makeSplashVM(profile: nil)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await recorder.drain()
        #expect(recorder.events == [.showMeetMochi])
    }

    // MARK: Identity summary details

    @Test("the summary prefers the profile name, falls back to the account, then 'Friend'")
    func summaryNameFallbacks() async {
        let membership = StubMembershipStore()
        membership.status = .lapsed

        // Profile has no name; account does.
        let (vm1, _, _, _) = makeSplashVM(profile: completedProfile(name: nil), membership: membership)
        let recorder1 = EventRecorder(vm1)
        await vm1.triggerAsync(.load)
        await recorder1.drain()
        guard case .showWelcomeBack(let s1) = recorder1.events.first else { return }
        #expect(s1.name == "Alex Rivera", "account displayName is the fallback")

        // Neither has a name.
        let auth = StubAuthRepository()
        auth.currentAccount = AuthAccount(uid: "user1", isAnonymous: false, displayName: nil, email: nil, providerId: "google.com")
        let (vm2, _, _, _) = makeSplashVM(auth: auth, profile: completedProfile(name: nil), membership: membership)
        let recorder2 = EventRecorder(vm2)
        await vm2.triggerAsync(.load)
        await recorder2.drain()
        guard case .showWelcomeBack(let s2) = recorder2.events.first else { return }
        #expect(s2.name == "Friend")
        #expect(s2.providerLabel == "Google")
        #expect(s2.detail == "Signed in", "no email must not render an empty line")
    }
}
