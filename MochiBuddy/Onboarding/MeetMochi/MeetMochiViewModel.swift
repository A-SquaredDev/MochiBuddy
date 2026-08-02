//
//  MeetMochiViewModel.swift
//  MochiBuddy
//
//  2 · Meet Mochi - the emotional hook: beaming baseline, the downswing,
//  recovery, then the naming beat that closes the meeting. Four beats on
//  one screen. Completing the naming beat (either button) stamps
//  adoptedOn; there is no wrong exit and no visible validation state
//  (sanitization is silent). No coin, no celebration - naming is a quiet,
//  warm moment, not a reward event.
//

import Foundation

final class MeetMochiViewModel: ObservableStateViewModel<
    MeetMochiBehavior.UIState,
    MeetMochiBehavior.ViewAction,
    MeetMochiBehavior.NavigationEvent
> {

    private let onboardingStore: OnboardingStore

    init(onboardingStore: OnboardingStore) {
        self.onboardingStore = onboardingStore
        super.init(initialState: MeetMochiBehavior.UIState())
    }

    override func triggerAsync(_ action: MeetMochiBehavior.ViewAction) async {
        switch action {
        case .continueTapped:
            if uiState.page.isNamingBeat {
                await completeNaming(rawName: uiState.nameDraft)
                return
            }
            let next = uiState.pageIndex + 1
            if next < MeetMochiBehavior.pages.count {
                show(page: next)
            } else {
                setNavigationEvent(.showFirstTask)
            }
        case .backTapped:
            let previous = uiState.pageIndex - 1
            if previous >= 0 {
                show(page: previous)
            }
        case .nameDraftChanged(let draft):
            setUIState(uiState.updating(\.nameDraft, to: draft))
        case .dismissSessionAlert:
            setUIState(uiState.updating(\.sessionFailed, to: false))
        case .keepDefaultTapped:
            await completeNaming(rawName: "")
        }
    }

    private func completeNaming(rawName: String) async {
        guard !uiState.isSaving else { return }
        setUIState(uiState.updating(\.isSaving, to: true))
        // The adoption is the wizard's first real write. Landing entries
        // arrive sessionless (splash no longer mints), and an offline
        // first run used to lose every choice silently - surface the
        // retry instead and keep the user on the naming beat.
        guard await onboardingStore.ensureSession() else {
            setUIState(
                uiState
                    .updating(\.isSaving, to: false)
                    .updating(\.sessionFailed, to: true)
            )
            return
        }
        await onboardingStore.completeNamingBeat(rawName: rawName)
        // The pushed screen keeps this view model alive; leaving isSaving
        // set would strand the CTA in a permanent spinner after back-nav.
        setUIState(uiState.updating(\.isSaving, to: false))
        setNavigationEvent(.showFirstTask)
    }

    private func show(page index: Int) {
        setUIState(
            uiState
                .updating(\.pageIndex, to: index)
                .updating(\.page, to: MeetMochiBehavior.pages[index])
                .updating(\.canGoBack, to: index > 0)
        )
    }
}
