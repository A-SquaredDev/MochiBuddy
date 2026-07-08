//
//  DeleteAccountFlowTests.swift
//  MochiBuddyTests
//
//  Account deletion is the one flow that must never half-succeed: the
//  billing warning must gate on a real entitlement, deletion must be
//  impossible without fresh proof of identity, and the Firestore subtree
//  must be erased STRICTLY BEFORE the Auth user disappears — security
//  rules lock an orphaned subtree forever.
//

import Foundation
import Testing
@testable import MochiBuddy

// MARK: - Step 1 · what gets erased

@Suite("Delete · warn screen")
@MainActor
struct DeleteWarnTests {

    private func makeVM(
        membership: StubMembershipStore = StubMembershipStore()
    ) -> (DeleteWarnViewModel, StubTaskRepository) {
        let taskRepo = StubTaskRepository()
        taskRepo.incomplete = (0..<10).map { makeTask(id: "t\($0)") }
        taskRepo.completed = (0..<4).map { makeTask(id: "c\($0)", completed: true, completedAt: .now) }
        let listRepo = StubListRepository()
        listRepo.lists = (0..<3).map { TaskList(id: "l\($0)", name: "L\($0)", colorHex: "#C9A6FF", icon: "🏷️", order: $0) }
        let profileRepo = StubProfileRepository()
        profileRepo.profile = makeProfile(coins: 128, streak: 4)
        let vm = DeleteWarnViewModel(
            authRepository: StubAuthRepository(),
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            listRepository: listRepo,
            membershipStore: membership
        )
        return (vm, taskRepo)
    }

    @Test("the warning shows real counts — what the user actually loses")
    func realCounts() async {
        let (vm, _) = makeVM()
        await vm.triggerAsync(.load)
        let byId = Dictionary(uniqueKeysWithValues: vm.uiState.items.map { ($0.id, $0.subtitle) })
        #expect(byId["tasks"] == "14 tasks across 4 lists") // 3 user lists + Inbox
        #expect(byId["coins"] == "128 ¢ balance")
        #expect(byId["streak"] == "4 days — reset to zero")
    }

    @Test("continue with an ACTIVE subscription detours through the billing warning")
    func activeDetours() async {
        let membership = StubMembershipStore()
        membership.status = .active(plan: .yearly, renewsAt: nil)
        let (vm, _) = makeVM(membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.continueTapped)
        await recorder.drain()
        #expect(recorder.events == [.showSubscriptionWarning])
    }

    @Test("a trial counts as active billing too")
    func trialDetours() async {
        let membership = StubMembershipStore()
        membership.status = .trial(endsAt: Dates.days(3))
        let (vm, _) = makeVM(membership: membership)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.continueTapped)
        await recorder.drain()
        #expect(recorder.events == [.showSubscriptionWarning])
    }

    @Test("no active billing skips straight to the final confirm")
    func unsubscribedSkips() async {
        for status in [MembershipStatus.lapsed, .notSubscribed] {
            let membership = StubMembershipStore()
            membership.status = status
            let (vm, _) = makeVM(membership: membership)
            let recorder = EventRecorder(vm)
            await vm.triggerAsync(.continueTapped)
            await recorder.drain()
            #expect(recorder.events == [.showFinalConfirm], "status \(status) should go to confirm")
        }
    }

    @Test("'Keep my account' backs all the way out")
    func keepCloses() async {
        let (vm, _) = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.keepTapped)
        await recorder.drain()
        #expect(recorder.events == [.close])
    }
}

// MARK: - Step 2 · billing keeps running

@Suite("Delete · billing warning")
@MainActor
struct DeleteSubActiveTests {

    private func makeVM() -> DeleteSubActiveViewModel {
        let membership = StubMembershipStore()
        membership.status = .active(plan: .yearly, renewsAt: nil)
        return DeleteSubActiveViewModel(membershipStore: membership)
    }

    @Test("the warning quotes the real price the user keeps paying")
    func priceLine() async {
        let vm = makeVM()
        await vm.triggerAsync(.load)
        #expect(vm.uiState.priceLine == "$29.99/yr")
    }

    @Test("'Delete anyway' is inert until the user acknowledges continued billing")
    func acknowledgmentGates() async {
        let vm = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.deleteAnywayTapped)
        await recorder.drain()
        #expect(recorder.events.isEmpty, "Apple requires explicit acknowledgment before deleting with live billing")

        await vm.triggerAsync(.toggleAcknowledged)
        await vm.triggerAsync(.deleteAnywayTapped)
        await recorder.drain()
        #expect(recorder.events == [.showFinalConfirm])
    }

    @Test("cancel backs all the way out")
    func cancel() async {
        let vm = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.cancelTapped)
        await recorder.drain()
        #expect(recorder.events == [.close])
    }
}

// MARK: - Step 3 · reauth + destroy

@Suite("Delete · final confirm")
@MainActor
struct DeleteConfirmTests {

    private func makeVM(
        auth: StubAuthRepository = StubAuthRepository()
    ) -> (DeleteConfirmViewModel, StubAuthRepository, StubAccountEraser, CallLog) {
        let eraser = StubAccountEraser()
        let log = CallLog()
        auth.callLog = log
        eraser.callLog = log
        let vm = DeleteConfirmViewModel(authRepository: auth, accountEraser: eraser)
        return (vm, auth, eraser, log)
    }

    @Test("an Apple account must re-verify with Apple")
    func appleNeedsReauth() async {
        let (vm, _, _, _) = makeVM()
        await vm.triggerAsync(.load)
        #expect(vm.uiState.method == .apple)
        #expect(vm.uiState.isVerified == false)
        #expect(vm.uiState.hashedNonce == "hashed-nonce")
    }

    @Test("a Google account must re-verify with Google")
    func googleNeedsReauth() async {
        let auth = StubAuthRepository()
        auth.currentAccount = AuthAccount(uid: "user1", isAnonymous: false, displayName: nil, email: nil, providerId: "google.com")
        let (vm, _, _, _) = makeVM(auth: auth)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.method == .google)
        #expect(vm.uiState.isVerified == false)
    }

    @Test("guest (anonymous) accounts skip reauth — Apple 5.1.1(v) covers them too")
    func anonymousIsPreVerified() async {
        let auth = StubAuthRepository()
        auth.currentAccount = AuthAccount(uid: "anon1", isAnonymous: true, displayName: nil, email: nil, providerId: nil)
        let (vm, _, eraser, _) = makeVM(auth: auth)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.method == DeleteConfirmBehavior.ReauthMethod.none)
        #expect(vm.uiState.isVerified == true, "a fresh anonymous session IS the recent login")

        // And the guest can actually delete.
        await vm.triggerAsync(.deleteTapped)
        #expect(eraser.erasedUserIds == ["anon1"])
    }

    @Test("delete without verification is a hard no-op — nothing is touched")
    func unverifiedDeleteRefused() async {
        let (vm, auth, eraser, _) = makeVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        #expect(eraser.erasedUserIds.isEmpty)
        #expect(auth.deleteCurrentUserCount == 0)
    }

    @Test("successful Apple reauth verifies with the raw nonce")
    func appleReauthVerifies() async {
        let (vm, auth, _, _) = makeVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.appleCompleted(idToken: "reauth-token"))
        #expect(vm.uiState.isVerified == true)
        let call = try! #require(auth.appleReauths.first)
        #expect(call.idToken == "reauth-token")
        #expect(call.rawNonce == "raw-nonce")
    }

    @Test("failed reauth stays unverified, surfaces the error, and rotates the nonce")
    func reauthFailure() async {
        let auth = StubAuthRepository()
        auth.reauthAppleError = TestError()
        let (vm, _, _, _) = makeVM(auth: auth)
        await vm.triggerAsync(.load)
        let noncesBefore = auth.makeNonceCount
        await vm.triggerAsync(.appleCompleted(idToken: "t"))
        #expect(vm.uiState.isVerified == false)
        #expect(vm.uiState.errorMessage != nil)
        #expect(auth.makeNonceCount == noncesBefore + 1)
    }

    @Test("cancelled Google reauth is quiet")
    func googleReauthCancelled() async {
        let auth = StubAuthRepository()
        auth.currentAccount = AuthAccount(uid: "user1", isAnonymous: false, displayName: nil, email: nil, providerId: "google.com")
        auth.reauthGoogleError = AuthRepositoryError.cancelled
        let (vm, _, _, _) = makeVM(auth: auth)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.googleTapped)
        #expect(vm.uiState.errorMessage == nil)
        #expect(vm.uiState.isVerified == false)
    }

    @Test("THE ordering invariant: Firestore data dies strictly before the Auth user")
    func eraseBeforeAuthDelete() async {
        let (vm, auth, eraser, log) = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.appleCompleted(idToken: "t"))
        await vm.triggerAsync(.deleteTapped)
        await recorder.drain()

        #expect(log.entries == ["eraseData", "deleteAuthUser"],
                "delete the auth user first and security rules lock the orphaned subtree forever")
        #expect(eraser.erasedUserIds == ["user1"], "must erase exactly the signed-in uid")
        #expect(auth.deleteCurrentUserCount == 1)
        #expect(recorder.events == [.deleted])
    }

    @Test("if the data erase fails, the Auth user SURVIVES — no orphaned data, retry stays possible")
    func eraseFailureAbortsAuthDelete() async {
        let auth = StubAuthRepository()
        let (vm, _, eraser, _) = makeVM(auth: auth)
        eraser.error = TestError()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.appleCompleted(idToken: "t"))
        await vm.triggerAsync(.deleteTapped)

        #expect(auth.deleteCurrentUserCount == 0,
                "deleting auth after a failed erase would strand the user's data forever")
        #expect(vm.uiState.errorMessage != nil)
        #expect(vm.uiState.isWorking == false, "the user must be able to retry")
    }

    @Test("if the auth delete itself fails, the error surfaces and the flow stays retryable")
    func authDeleteFailure() async {
        let auth = StubAuthRepository()
        auth.deleteError = TestError()
        let (vm, _, _, _) = makeVM(auth: auth)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.appleCompleted(idToken: "t"))
        await vm.triggerAsync(.deleteTapped)
        await recorder.drain()

        #expect(recorder.events.isEmpty, "must not pretend deletion happened")
        #expect(vm.uiState.errorMessage != nil)
        #expect(vm.uiState.isWorking == false)
    }

    @Test("'Keep my account' closes without touching anything")
    func keepIsSafe() async {
        let (vm, auth, eraser, _) = makeVM()
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.keepTapped)
        await recorder.drain()
        #expect(recorder.events == [.close])
        #expect(eraser.erasedUserIds.isEmpty)
        #expect(auth.deleteCurrentUserCount == 0)
    }
}
