//
//  FlavorPickerViewModel.swift
//  MochiBuddy
//
//  4 · Choose Mochi's flavor — recolors the whole app live. All included.
//

import Foundation

final class FlavorPickerViewModel: ObservableStateViewModel<
    FlavorPickerBehavior.UIState,
    FlavorPickerBehavior.ViewAction,
    FlavorPickerBehavior.NavigationEvent
> {

    private let onboardingStore: OnboardingStore

    init(onboardingStore: OnboardingStore) {
        self.onboardingStore = onboardingStore
        super.init(initialState: FlavorPickerBehavior.UIState())
    }

    override func triggerAsync(_ action: FlavorPickerBehavior.ViewAction) async {
        switch action {
        case .load:
            let items = MochiTheme.all.map { theme in
                FlavorPickerBehavior.FlavorUIItem(
                    id: theme.id,
                    name: theme.name,
                    bg: theme.bg,
                    primary: theme.primary,
                    pet: theme.pet,
                    ink: theme.ink
                )
            }
            setUIState(
                uiState
                    .updating(\.flavors, to: items)
                    .updating(\.selectedId, to: onboardingStore.selectedThemeId)
            )

        case .select(let id):
            onboardingStore.selectTheme(id: id)
            state.selectedId = id

        case .continueTapped:
            setNavigationEvent(.next)
        }
    }
}
