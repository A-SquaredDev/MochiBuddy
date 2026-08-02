//
//  FirstTaskViewModel.swift
//  MochiBuddy
//
//  3 · Add your first task - the activation moment. Skippable, but this is
//  where the loop clicks with the user's own data.
//

import Foundation

final class FirstTaskViewModel: ObservableStateViewModel<
    FirstTaskBehavior.UIState,
    FirstTaskBehavior.ViewAction,
    FirstTaskBehavior.NavigationEvent
> {

    private let onboardingStore: OnboardingStore

    // Domain source of truth - UIState is derived from it.
    private var draft = TaskDraft(title: "")

    init(onboardingStore: OnboardingStore) {
        self.onboardingStore = onboardingStore
        super.init(initialState: FirstTaskBehavior.UIState(petName: onboardingStore.petName))
    }

    override func triggerAsync(_ action: FirstTaskBehavior.ViewAction) async {
        switch action {
        case .titleChanged(let title):
            draft.title = title
            rebuildState()

        case .suggestionTapped(let suggestion):
            draft.title = suggestion.trimmingCharacters(in: .whitespaces)
            rebuildState()

        case .timeChoiceTapped(let choice):
            state.timeChoice = choice

        case .addTapped:
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            state.isSaving = true
            // Due today like every other capture path - a first task that
            // lands in Someday and never notifies is a broken first
            // impression. The slot chips add an actual reminder time.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let dueAt = uiState.timeChoice.minuteOfDay.map { minute in
                calendar.date(
                    bySettingHour: minute / 60, minute: minute % 60, second: 0, of: today
                ) ?? today
            } ?? today
            await onboardingStore.saveFirstTask(
                title: title,
                dueAt: dueAt,
                hasTime: uiState.timeChoice.minuteOfDay != nil
            )
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
