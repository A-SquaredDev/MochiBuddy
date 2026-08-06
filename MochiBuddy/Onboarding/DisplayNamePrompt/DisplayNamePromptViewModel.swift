//
//  DisplayNamePromptViewModel.swift
//  MochiBuddy
//
//  The one-time "What should Mochi call you?" ask. Saving writes the
//  profile display name; skipping records the gate flag so the sheet never
//  comes back for this UID. Both exits dismiss - there is no wrong answer
//  and no validation state, same posture as the pet naming beat.
//

import Foundation

final class DisplayNamePromptViewModel: ObservableStateViewModel<
    DisplayNamePromptBehavior.UIState,
    DisplayNamePromptBehavior.ViewAction,
    DisplayNamePromptBehavior.NavigationEvent
> {

    private let userId: String
    private let profileRepository: UserProfileRepository
    private let gate: DisplayNamePromptGate

    init(
        userId: String,
        petName: String,
        profileRepository: UserProfileRepository,
        gate: DisplayNamePromptGate
    ) {
        self.userId = userId
        self.profileRepository = profileRepository
        self.gate = gate
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

        case .skipTapped:
            // Recorded, not just dismissed: without the flag the sheet
            // would greet this account on every single launch.
            gate.recordSkipped(userId: userId)
            setNavigationEvent(.dismiss)
        }
    }
}
