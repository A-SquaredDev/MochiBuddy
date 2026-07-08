//
//  ReminderSettingsViewModel.swift
//  MochiBuddy
//
//  Apple Reminders in Settings — connect (EventKit full access), pick
//  which lists Mochi watches, or stop syncing. Tasks stay in EventKit;
//  only the chosen list ids live on the profile.
//

import Foundation

final class ReminderSettingsViewModel: StateViewModel<
    ReminderSettingsBehavior.UIState,
    ReminderSettingsBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let remindersGateway: RemindersGateway

    // Domain source of truth.
    private var availableLists: [ReminderList] = []
    private var syncedIds: [String] = []

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        remindersGateway: RemindersGateway
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.remindersGateway = remindersGateway
        super.init(initialState: ReminderSettingsBehavior.UIState())
    }

    override func triggerAsync(_ action: ReminderSettingsBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId, let profile = try? await profileRepository.fetchProfile(userId: userId) {
                syncedIds = profile.importedReminderListIds
            }
            switch remindersGateway.accessStatus {
            case .granted:
                availableLists = await remindersGateway.fetchLists()
                rebuildState(status: .connected)
            case .notDetermined:
                rebuildState(status: .disconnected)
            case .denied:
                rebuildState(status: .systemDenied)
            }

        case .connectTapped:
            state.isConnecting = true
            let granted = await remindersGateway.requestFullAccess()
            state.isConnecting = false
            if granted {
                availableLists = await remindersGateway.fetchLists()
                rebuildState(status: .connected)
            } else {
                rebuildState(status: .systemDenied)
            }

        case .setListSyncing(let id, let isOn):
            if isOn {
                if !syncedIds.contains(id) {
                    syncedIds.append(id)
                }
            } else {
                syncedIds.removeAll { $0 == id }
            }
            rebuildState(status: uiState.status)
            await persist()

        case .disconnectTapped:
            syncedIds = []
            rebuildState(status: uiState.status)
            await persist()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func persist() async {
        guard let userId else { return }
        try? await profileRepository.saveImportedReminderLists(syncedIds, userId: userId)
    }

    private func rebuildState(status: ReminderSettingsBehavior.Status) {
        let items = availableLists.map { list in
            ReminderSettingsBehavior.ListUIItem(
                id: list.id,
                name: list.name,
                countText: "\(list.incompleteCount) reminder\(list.incompleteCount == 1 ? "" : "s")",
                isSyncing: syncedIds.contains(list.id)
            )
        }
        setUIState(
            uiState
                .updating(\.status, to: status)
                .updating(\.lists, to: items)
                .updating(\.syncingCount, to: items.filter(\.isSyncing).count)
        )
    }
}
