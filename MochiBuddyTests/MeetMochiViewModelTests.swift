//
//  MeetMochiViewModelTests.swift
//  MochiBuddyTests
//
//  The wizard's first write is the adoption, and Landing entries arrive
//  sessionless (splash no longer mints). The naming beat must mint the
//  session itself and surface a visible retry when it can't - an offline
//  first run used to lose every onboarding choice silently.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeMeetMochiVM(
    auth: StubAuthRepository = StubAuthRepository()
) -> (MeetMochiViewModel, StubAuthRepository, StubProfileRepository) {
    let profileRepo = StubProfileRepository()
    let defaults = UserDefaults(suiteName: "meet-mochi-\(UUID())")!
    let store = OnboardingStore(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: StubTaskRepository(),
        themeStore: ThemeStore(defaults: defaults),
        petIdentityStore: PetIdentityStore(profileRepository: profileRepo, defaults: defaults)
    )
    return (MeetMochiViewModel(onboardingStore: store), auth, profileRepo)
}

@Suite("MeetMochi · sessionless naming beat")
@MainActor
struct MeetMochiViewModelTests {

    @Test("naming with no session and no connection shows the retry, loses nothing silently")
    func offlineNamingSurfacesRetry() async {
        let auth = StubAuthRepository()
        auth.currentAccount = nil
        let (vm, _, _) = makeMeetMochiVM(auth: auth)
        let recorder = EventRecorder(vm)

        await vm.triggerAsync(.keepDefaultTapped)
        await recorder.drain()

        #expect(recorder.events.isEmpty, "the flow must not advance past an unsaved adoption")
        #expect(vm.uiState.sessionFailed, "the connection alert is the visible retry")
        #expect(vm.uiState.isSaving == false, "the button stays usable for the retry")
    }

    @Test("once connectivity returns, the same tap mints, saves, and advances")
    func retryAfterReconnect() async {
        let auth = StubAuthRepository()
        auth.currentAccount = nil
        let (vm, _, _) = makeMeetMochiVM(auth: auth)
        let recorder = EventRecorder(vm)
        await vm.triggerAsync(.keepDefaultTapped)
        await vm.triggerAsync(.dismissSessionAlert)
        #expect(vm.uiState.sessionFailed == false)

        // Connectivity (and thus the mint) is back.
        auth.currentAccount = AuthAccount(
            uid: "anon1", isAnonymous: true, displayName: nil, email: nil, providerId: nil
        )
        await vm.triggerAsync(.keepDefaultTapped)
        await recorder.drain()

        #expect(recorder.events == [.showFirstTask])
        #expect(vm.uiState.sessionFailed == false)
        #expect(
            vm.uiState.isSaving == false,
            "the pushed screen keeps this VM alive; a stuck isSaving strands the CTA after back-nav"
        )
    }

    @Test("navigating back after a successful save leaves the button usable")
    func backAfterSaveKeepsButtonUsable() async {
        let (vm, _, _) = makeMeetMochiVM()

        // Walk to the naming beat, save, then come back to it.
        while !vm.uiState.page.isNamingBeat {
            await vm.triggerAsync(.continueTapped)
        }
        await vm.triggerAsync(.keepDefaultTapped)
        await vm.triggerAsync(.backTapped)

        #expect(vm.uiState.isSaving == false)
    }
}
