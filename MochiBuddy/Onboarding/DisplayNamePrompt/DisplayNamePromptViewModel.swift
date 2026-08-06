//
//  DisplayNamePromptViewModel.swift
//  MochiBuddy
//
//  The "What should Mochi call you?" ask. Saving writes the profile
//  display name, which closes the ask for good: the prompt only fires on
//  an empty name, so a saved name is its own done-flag. There is no skip -
//  the greeting name is required, so the sheet asks until it has one.
//

import Foundation

final class DisplayNamePromptViewModel: ObservableStateViewModel<
    DisplayNamePromptBehavior.UIState,
    DisplayNamePromptBehavior.ViewAction,
    DisplayNamePromptBehavior.NavigationEvent
> {

    private let userId: String
    private let profileRepository: UserProfileRepository

    init(
        userId: String,
        petName: String,
        profileRepository: UserProfileRepository
    ) {
        self.userId = userId
        self.profileRepository = profileRepository
        var initial = DisplayNamePromptBehavior.UIState()
        initial.mochiName = petName
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: DisplayNamePromptBehavior.ViewAction) async {
        switch action {
        case .draftChanged(let draft):
            setUIState(
                uiState
                    .updating(\.draft, to: draft)
                    .updating(
                        \.canSave,
                        to: !draft.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            )

        case .saveTapped:
            let name = uiState.draft.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !uiState.isSaving else { return }
            setUIState(uiState.updating(\.isSaving, to: true))
            try? await profileRepository.saveDisplayName(name, userId: userId)
            setUIState(uiState.updating(\.isSaving, to: false))
            setNavigationEvent(.dismiss)
        }
    }
}
