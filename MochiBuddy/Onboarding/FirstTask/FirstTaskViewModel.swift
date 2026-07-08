//
//  FirstTaskViewModel.swift
//  MochiBuddy
//
//  3 · Add your first task — the activation moment. Skippable, but this is
//  where the loop clicks with the user's own data.
//

import Foundation

final class FirstTaskViewModel: ObservableStateViewModel<
    FirstTaskBehavior.UIState,
    FirstTaskBehavior.ViewAction,
    FirstTaskBehavior.NavigationEvent
> {

    private let onboardingStore: OnboardingStore

    // Domain source of truth — UIState is derived from it.
    private var draft = TaskDraft(title: "")

    init(onboardingStore: OnboardingStore) {
        self.onboardingStore = onboardingStore
        super.init(initialState: FirstTaskBehavior.UIState())
    }

    override func triggerAsync(_ action: FirstTaskBehavior.ViewAction) async {
        switch action {
        case .titleChanged(let title):
            draft.title = title
            rebuildState()

        case .suggestionTapped(let suggestion):
            draft.title = suggestion.trimmingCharacters(in: .whitespaces)
            rebuildState()

        case .addTapped:
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            state.isSaving = true
            await onboardingStore.saveFirstTask(title: title)
            state.isSaving = false
            setNavigationEvent(.next)

        case .skipTapped:
            setNavigationEvent(.next)
        }
    }

    private func rebuildState() {
        setUIState(
            uiState
                .updating(\.title, to: draft.title)
                .updating(\.canAdd, to: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
    }
}
