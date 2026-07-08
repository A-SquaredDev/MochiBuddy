//
//  AccountLinkingTests.swift
//  MochiBuddyTests
//
//  Continue with Apple / Google — the anonymous session is linked, the
//  display name travels to the profile document, and purchases follow
//  whichever uid we actually end up signed in as.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeAccountVM(
    auth: StubAuthRepository = StubAuthRepository()
) -> (AccountViewModel, StubAuthRepository, StubProfileRepository, StubMembershipStore) {
    let profileRepo = StubProfileRepository()
    let membership = StubMembershipStore()
    let onboardingStore = OnboardingStore(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: StubTaskRepository(),
        themeStore: ThemeStore(defaults: UserDefaults(suiteName: "mochi-tests-\(UUID())")!)
    )
    let vm = AccountViewModel(
        authRepository: auth,
        onboardingStore: onboardingStore,
        membershipStore: membership
    )
    return (vm, auth, profileRepo, membership)
}

@Suite("Account linking · Sign in with Apple")
@MainActor
struct AppleLinkingTests {

    @Test("load exposes the hashed nonce for the Apple request")
    func noncePrepared() async {
        let (vm, auth, _, _) = makeAccountVM()
        await vm.triggerAsync(.load)
        #expect(vm.uiState.hashedNonce == "hashed-nonce")
        #expect(auth.makeNonceCount == 1)
    }

    @Test("completing Apple sign-in passes the RAW nonce and the full name through")
    func nonceAndNameTravel() async {
        let (vm, auth, _, _) = makeAccountVM()
        await vm.triggerAsync(.load)

        var name = PersonNameComponents()
        name.givenName = "Alex"
        name.familyName = "Rivera"
        await vm.triggerAsync(.appleCompleted(idToken: "id-token-123", fullName: name))

        let call = try! #require(auth.appleSignIns.first)
        #expect(call.idToken == "id-token-123")
        #expect(call.rawNonce == "raw-nonce", "Firebase needs the raw nonce that hashes to the request's")
        #expect(call.fullName == name, "Apple only provides the name ONCE — losing it here loses it forever")
    }

    @Test("the linked account's name and provider land on the profile document")
    func nameReachesProfile() async {
        let (vm, auth, profileRepo, _) = makeAccountVM()
        auth.signInResult = AuthAccount(
            uid: "user1", isAnonymous: false, displayName: "Alex Rivera",
            email: "alex@hey.com", providerId: "apple.com"
        )
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.appleCompleted(idToken: "t", fullName: nil))

        let link = try! #require(profileRepo.accountLinks.first)
        #expect(link.provider == "apple.com")
        #expect(link.displayName == "Alex Rivera")
    }

    @Test("purchases follow the uid we actually became — even when the credential belonged to an existing account")
    func identifyFollowsActualUid() async {
        let (vm, auth, _, membership) = makeAccountVM()
        // The Apple credential already had a Mochi account: sign-in lands on
        // a DIFFERENT uid than the anonymous session.
        auth.signInResult = AuthAccount(
            uid: "existing-user-42", isAnonymous: false, displayName: "Old Alex",
            email: "alex@hey.com", providerId: "apple.com"
        )
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.appleCompleted(idToken: "t", fullName: nil))
        #expect(membership.identifiedUserIds == ["existing-user-42"],
                "RevenueCat must be re-pointed or the subscription follows the dead anonymous uid")
    }

    @Test("a completion without a prepared nonce is refused outright")
    func noNonceNoSignIn() async {
        let (vm, auth, _, _) = makeAccountVM()
        // No .load — pendingNonce was never created.
        await vm.triggerAsync(.appleCompleted(idToken: "t", fullName: nil))
        #expect(auth.appleSignIns.isEmpty, "must never call Firebase with an unverifiable nonce")
        #expect(vm.uiState.errorMessage != nil)
    }

    @Test("an Apple failure surfaces the error, stops the spinner, and rotates the nonce")
    func failureRotatesNonce() async {
        let (vm, auth, _, _) = makeAccountVM()
        auth.appleSignInError = TestError()
        await vm.triggerAsync(.load)
        let noncesBefore = auth.makeNonceCount
        await vm.triggerAsync(.appleCompleted(idToken: "t", fullName: nil))
        #expect(vm.uiState.errorMessage?.contains("Apple") == true)
        #expect(vm.uiState.isWorking == false)
        #expect(auth.makeNonceCount == noncesBefore + 1, "a nonce is single-use — retry needs a fresh one")
    }

    @Test("user-cancelled Apple sign-in shows no error but still rotates the nonce")
    func cancelledIsQuiet() async {
        let (vm, auth, _, _) = makeAccountVM()
        await vm.triggerAsync(.load)
        let noncesBefore = auth.makeNonceCount
        await vm.triggerAsync(.appleFailed(message: ""))
        #expect(vm.uiState.errorMessage == nil)
        #expect(auth.makeNonceCount == noncesBefore + 1)
    }
}

@Suite("Account linking · Google")
@MainActor
struct GoogleLinkingTests {

    @Test("Google success links, mirrors the name, and re-points purchases")
    func googleSuccess() async {
        let auth = StubAuthRepository()
        auth.signInResult = AuthAccount(
            uid: "user1", isAnonymous: false, displayName: "Alex Rivera",
            email: "alex@gmail.com", providerId: "google.com"
        )
        let (vm, _, profileRepo, membership) = makeAccountVM(auth: auth)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.googleTapped)

        let link = try! #require(profileRepo.accountLinks.first)
        #expect(link.provider == "google.com")
        #expect(link.displayName == "Alex Rivera", "the Google profile name must reach Firestore")
        #expect(membership.identifiedUserIds == ["user1"])
        #expect(vm.uiState.errorMessage == nil)
    }

    @Test("cancelling the Google sheet is not an error")
    func googleCancelled() async {
        let auth = StubAuthRepository()
        auth.googleSignInError = AuthRepositoryError.cancelled
        let (vm, _, profileRepo, _) = makeAccountVM(auth: auth)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.googleTapped)
        #expect(vm.uiState.errorMessage == nil)
        #expect(vm.uiState.isWorking == false)
        #expect(profileRepo.accountLinks.isEmpty)
    }

    @Test("Google not configured shows the dedicated notice, not a scary error")
    func googleUnavailable() async {
        let auth = StubAuthRepository()
        auth.googleSignInError = AuthRepositoryError.providerUnavailable("Google")
        let (vm, _, _, _) = makeAccountVM(auth: auth)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.googleTapped)
        #expect(vm.uiState.showGoogleUnavailable == true)
        #expect(vm.uiState.errorMessage == nil)
    }

    @Test("a real Google failure surfaces an error and stops the spinner")
    func googleFailure() async {
        let auth = StubAuthRepository()
        auth.googleSignInError = TestError()
        let (vm, _, _, _) = makeAccountVM(auth: auth)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.googleTapped)
        #expect(vm.uiState.errorMessage?.contains("Google") == true)
        #expect(vm.uiState.isWorking == false)
    }
}
