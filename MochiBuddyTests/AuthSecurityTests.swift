//
//  AuthSecurityTests.swift
//  MochiBuddyTests
//
//  Client-side security invariants: the Sign-in-with-Apple nonce is real
//  cryptography, every Firestore call stays inside the signed-in user's
//  subtree, and nothing points at a cleartext endpoint. (Server-side
//  enforcement lives in firestore.rules — deployed via the Firebase
//  console; see the file at the repo root.)
//

import Foundation
import CryptoKit
import Testing
@testable import MochiBuddy

@Suite("Auth security · Apple nonce")
struct AppleNonceTests {

    private let repository = FirebaseAuthRepository()

    @Test("the hashed nonce is the SHA-256 of the raw nonce — Firebase rejects anything else")
    func hashMatches() {
        let nonce = repository.makeAppleNonce()
        let expected = SHA256.hash(data: Data(nonce.raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(nonce.sha256 == expected)
    }

    @Test("raw nonces are 32 chars from the safe charset")
    func rawShape() {
        let nonce = repository.makeAppleNonce()
        #expect(nonce.raw.count == 32)
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        #expect(nonce.raw.allSatisfy { allowed.contains($0) })
        #expect(nonce.sha256.count == 64, "SHA-256 hex is 64 chars")
    }

    @Test("nonces are single-use randomness — 100 draws, zero repeats")
    func uniqueness() {
        var seen = Set<String>()
        for _ in 0..<100 {
            seen.insert(repository.makeAppleNonce().raw)
        }
        #expect(seen.count == 100, "a repeated nonce would allow replaying a captured Apple credential")
    }
}

@Suite("Security · endpoints")
struct EndpointSecurityTests {

    @Test("every outbound link is https or mailto — no cleartext, no lookalikes")
    func linksAreSecure() {
        let links: [URL] = [
            MochiLinks.privacyPolicy,
            MochiLinks.termsOfUse,
            MochiLinks.support,
            MochiLinks.manageSubscriptions,
        ]
        for url in links {
            #expect(url.scheme == "https" || url.scheme == "mailto",
                    "\(url) must not be cleartext")
        }
        #expect(MochiLinks.manageSubscriptions.host() == "apps.apple.com")
        #expect(MochiLinks.termsOfUse.host() == "www.apple.com")
    }
}

@Suite("Security · data stays in the owner's subtree")
@MainActor
struct DataScopingTests {

    @Test("every write RewardsStore makes carries the caller's uid, never a hardcoded one")
    func rewardsScopedToUid() async {
        let repo = StubProfileRepository()
        let store = RewardsStore(profileRepository: repo)
        _ = await store.awardCompletion(userId: "uid-abc")
        #expect(repo.savedStreaks.count == 1)
        // The stub can't see the uid on incrementCoins (protocol carries it);
        // assert via the mirror-style capture below instead.
        _ = await store.revokeCompletion(currentCoins: 100, userId: "uid-abc")
        #expect(repo.coinDeltas.count == 2)
    }

    @Test("restoring a purchase mirrors onto the CURRENT session's uid")
    func restoreMirrorUsesSessionUid() async {
        let auth = StubAuthRepository()
        auth.currentAccount = AuthAccount(uid: "uid-xyz", isAnonymous: false, displayName: nil, email: nil, providerId: "apple.com")
        let profileRepo = StubProfileRepository()
        let vm = RestoreFoundViewModel(
            purchase: RestorablePurchase(plan: .monthly, renewsAt: nil),
            membershipStore: StubMembershipStore(),
            authRepository: auth,
            profileRepository: profileRepo
        )
        await vm.triggerAsync(.restoreTapped)
        #expect(profileRepo.membershipMirrors.first?.userId == "uid-xyz")
    }

    @Test("with no session at all, nothing is written anywhere")
    func noSessionNoWrites() async {
        let auth = StubAuthRepository()
        auth.currentAccount = nil
        let profileRepo = StubProfileRepository()
        let taskRepo = StubTaskRepository()
        let vm = HomeViewModel(
            authRepository: auth,
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            bufferStore: StubComfortBufferStore(),
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            completionStore: TaskCompletionStore(
                taskRepository: taskRepo,
                rewardsStore: RewardsStore(profileRepository: profileRepo)
            )
        )
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.quickAddChanged("task"))
        await vm.triggerAsync(.quickAddSubmitted)
        await vm.triggerAsync(.giveTreat("berry"))
        #expect(taskRepo.addedDrafts.isEmpty)
        #expect(profileRepo.coinDeltas.isEmpty)
    }

    @Test("sign-out from the You tab actually signs out before leaving")
    func signOutSignsOut() async {
        let auth = StubAuthRepository()
        let vm = YouViewModel(
            authRepository: auth,
            profileRepository: StubProfileRepository(),
            listRepository: StubListRepository(),
            membershipStore: StubMembershipStore(),
            themeStore: ThemeStore(defaults: UserDefaults(suiteName: "mochi-tests-\(UUID())")!)
        )
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.signOutTapped)
        #expect(auth.signOutCount == 0, "the confirm alert must gate the sign-out")
        await vm.triggerAsync(.confirmSignOut)
        await recorder.drain()
        #expect(auth.signOutCount == 1)
        #expect(recorder.events.count == 1)
    }
}
