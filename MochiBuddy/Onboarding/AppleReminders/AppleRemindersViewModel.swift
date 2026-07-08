//
//  AppleRemindersViewModel.swift
//  MochiBuddy
//
//  7 · Apple Reminders import — optional and skippable (high-trust ask;
//  also offered later in Settings). The EventKit prompt only fires after
//  the user opts in, then they pick which lists Mochi may watch.
//

import Foundation

final class AppleRemindersViewModel: ObservableStateViewModel<
    AppleRemindersBehavior.UIState,
    AppleRemindersBehavior.ViewAction,
    AppleRemindersBehavior.NavigationEvent
> {

    private let remindersGateway: RemindersGateway
    private let onboardingStore: OnboardingStore

    private var availableLists: [ReminderList] = []
    private var selectedListIds = Set<String>()

    init(remindersGateway: RemindersGateway, onboardingStore: OnboardingStore) {
        self.remindersGateway = remindersGateway
        self.onboardingStore = onboardingStore
        super.init(initialState: AppleRemindersBehavior.UIState())
    }

    override func triggerAsync(_ action: AppleRemindersBehavior.ViewAction) async {
        switch action {
        case .primaryTapped:
            switch uiState.phase {
            case .primer:
                await requestAccessAndLoadLists()
            case .picking:
                state.isWorking = true
                await onboardingStore.saveImportedReminderLists(ids: Array(selectedListIds))
                state.isWorking = false
                setNavigationEvent(.next)
            }

        case .toggleList(let id):
            if selectedListIds.contains(id) {
                selectedListIds.remove(id)
            } else {
                selectedListIds.insert(id)
            }
            rebuildListState()

        case .skipTapped:
            setNavigationEvent(.next)
        }
    }

    private func requestAccessAndLoadLists() async {
        state.isWorking = true
        let granted = await remindersGateway.requestFullAccess()
        guard granted else {
            // Denied is fine — the import stays available in Settings.
            state.isWorking = false
            setNavigationEvent(.next)
            return
        }

        let lists = await remindersGateway.fetchLists()
        guard !lists.isEmpty else {
            state.isWorking = false
            setNavigationEvent(.next)
            return
        }

        availableLists = lists
        selectedListIds = Set(lists.map(\.id))
        state.isWorking = false
        state.phase = .picking
        rebuildListState()
    }

    private func rebuildListState() {
        let items = availableLists.map { list in
            AppleRemindersBehavior.ListUIItem(
                id: list.id,
                name: list.name,
                countText: "\(list.incompleteCount) reminders",
                isOn: selectedListIds.contains(list.id)
            )
        }
        let count = selectedListIds.count
        setUIState(
            uiState
                .updating(\.lists, to: items)
                .updating(\.ctaTitle, to: count == 0 ? "Continue without importing" : "Import \(count) \(count == 1 ? "list" : "lists")")
        )
    }
}
