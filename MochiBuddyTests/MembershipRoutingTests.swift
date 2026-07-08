//
//  MembershipRoutingTests.swift
//  MochiBuddyTests
//
//  Subscription state decides where returning users land: subscribed goes
//  home, an Apple-ID purchase found after reinstall restores for free, and
//  everyone else meets the lapsed gate / paywall. No unsubscribed slip-ins,
//  no subscribed user ever re-charged.
//

import Foundation
import Testing
@testable import MochiBuddy

private let summary = ReturningAccountSummary(name: "Alex", detail: "alex@hey.com", providerLabel: "Apple ID")

@Suite("WelcomeBack · membership routing")
@MainActor
struct WelcomeBackRoutingTests {

    private func makeVM(_ membership: StubMembershipStore) -> WelcomeBackViewModel {
        WelcomeBackViewModel(summary: summary, membershipStore: membership)
    }

    @Test("an active membership enters the app directly")
    func activeEnters() async {
        let membership = StubMembershipStore()
        membership.status = .active(plan: .yearly, renewsAt: nil)
        let vm = makeVM(membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.continueTapped)
        await recorder.drain()
        #expect(recorder.events == [.enterApp])
    }

    @Test("a live trial enters the app directly")
    func trialEnters() async {
        let membership = StubMembershipStore()
        membership.status = .trial(endsAt: Date.now.addingTimeInterval(24 * 3600))
        let vm = makeVM(membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.continueTapped)
        await recorder.drain()
        #expect(recorder.events == [.enterApp])
    }

    @Test("reinstall after deleting the app: the Apple ID still holds the purchase → free restore, never a re-charge")
    func restorablePurchaseOffered() async {
        let membership = StubMembershipStore()
        membership.status = .notSubscribed // fresh install knows nothing yet
        let purchase = RestorablePurchase(plan: .yearly, renewsAt: Dates.days(200))
        membership.restorable = purchase
        let vm = makeVM(membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.continueTapped)
        await recorder.drain()
        #expect(recorder.events == [.showRestoreFound(purchase)])
    }

    @Test("lapsed with nothing to restore hits the lapsed gate")
    func lapsedGated() async {
        let membership = StubMembershipStore()
        membership.status = .lapsed
        let vm = makeVM(membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.continueTapped)
        await recorder.drain()
        #expect(recorder.events == [.showLapsedGate])
    }

    @Test("'Not you?' restarts onboarding")
    func switchAccount() async {
        let vm = makeVM(StubMembershipStore())
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.switchAccountTapped)
        await recorder.drain()
        #expect(recorder.events == [.restartOnboarding])
    }
}

@Suite("RestoreFound")
@MainActor
struct RestoreFoundTests {

    @Test("restoring re-activates the purchase and mirrors it onto the right uid")
    func restoreMirrors() async {
        let membership = StubMembershipStore()
        let auth = StubAuthRepository()
        let profileRepo = StubProfileRepository()
        let purchase = RestorablePurchase(plan: .yearly, renewsAt: Dates.days(100))
        let vm = RestoreFoundViewModel(
            purchase: purchase,
            membershipStore: membership,
            authRepository: auth,
            profileRepository: profileRepo
        )
        await vm.triggerAsync(.restoreTapped)

        #expect(membership.restoredPurchases == [purchase])
        let mirror = try! #require(profileRepo.membershipMirrors.first)
        #expect(mirror.isSubscribed == true)
        #expect(mirror.userId == "user1")
    }
}

@Suite("Paywall · subscribing")
@MainActor
struct PaywallTests {

    @MainActor
    private func makeVM(
        membership: StubMembershipStore = StubMembershipStore()
    ) -> (PaywallViewModel, StubMembershipStore, StubProfileRepository) {
        let profileRepo = StubProfileRepository()
        let onboardingStore = OnboardingStore(
            authRepository: StubAuthRepository(),
            profileRepository: profileRepo,
            taskRepository: StubTaskRepository(),
            themeStore: ThemeStore(defaults: UserDefaults(suiteName: "mochi-tests-\(UUID())")!)
        )
        let vm = PaywallViewModel(membershipStore: membership, onboardingStore: onboardingStore)
        return (vm, membership, profileRepo)
    }

    @Test("a successful trial start mirrors the subscription with its end date and moves on")
    func trialSuccess() async {
        let (vm, membership, profileRepo) = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.startTrialTapped)
        await recorder.drain()

        #expect(membership.startedTrials == [.yearly], "yearly is the default selection")
        let mirror = try! #require(profileRepo.membershipMirrors.first)
        #expect(mirror.isSubscribed == true)
        #expect(mirror.trialEndsAt != nil, "the trial end date must be mirrored for the profile")
        #expect(recorder.events.count == 1)
        #expect(vm.uiState.isPurchasing == false)
    }

    @Test("cancelling the purchase sheet is quiet — no error, no navigation, no mirror")
    func purchaseCancelled() async {
        let membership = StubMembershipStore()
        membership.purchaseError = MembershipStoreError.cancelled
        let (vm, _, profileRepo) = makeVM(membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.startTrialTapped)
        await recorder.drain()

        #expect(recorder.events.isEmpty)
        #expect(vm.uiState.restoreMessage == nil)
        #expect(vm.uiState.isPurchasing == false)
        #expect(profileRepo.membershipMirrors.isEmpty, "a cancelled purchase must never mark the profile subscribed")
    }

    @Test("a failed purchase reports and never fakes a subscription")
    func purchaseFailure() async {
        let membership = StubMembershipStore()
        membership.purchaseError = MembershipStoreError.purchaseFailed
        let (vm, _, profileRepo) = makeVM(membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.startTrialTapped)
        await recorder.drain()

        #expect(recorder.events.isEmpty)
        #expect(vm.uiState.restoreMessage != nil)
        #expect(profileRepo.membershipMirrors.isEmpty)
    }

    @Test("restore on the paywall finds the Apple-ID purchase and continues")
    func paywallRestore() async {
        let membership = StubMembershipStore()
        membership.restorable = RestorablePurchase(plan: .monthly, renewsAt: nil)
        let (vm, _, profileRepo) = makeVM(membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.restoreTapped)
        await recorder.drain()

        #expect(membership.restoredPurchases.count == 1)
        #expect(profileRepo.membershipMirrors.first?.isSubscribed == true)
        #expect(recorder.events.count == 1)
    }

    @Test("restore with nothing on the Apple ID explains itself and stays put")
    func paywallRestoreEmpty() async {
        let (vm, _, profileRepo) = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.restoreTapped)
        await recorder.drain()

        #expect(recorder.events.isEmpty)
        #expect(vm.uiState.restoreMessage?.contains("No previous") == true)
        #expect(profileRepo.membershipMirrors.isEmpty)
    }
}
