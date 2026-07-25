//
//  ManageListsViewModel.swift
//  MochiBuddy
//
//  Manage lists - create, rename, reorder, remove. Tasks in a deleted
//  list fall back to the Inbox (list resolution is the task surface's job).
//

import SwiftUI

final class ManageListsViewModel: StateViewModel<
    ManageListsBehavior.UIState,
    ManageListsBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let listRepository: ListRepository

    // Domain source of truth.
    private var lists: [TaskList] = []
    private var deleteCandidateId: String?
    private var renameCandidateId: String?
    /// After create clears the field, the focused TextField can echo the
    /// old draft back - swallow that exact string until different input.
    private var lastCreatedDraftName: String?

    init(
        authRepository: AuthRepository,
        listRepository: ListRepository,
        membershipSession: MembershipSession,
        petName: String = "Mochi"
    ) {
        self.authRepository = authRepository
        self.listRepository = listRepository
        var initial = ManageListsBehavior.UIState()
        initial.petName = petName
        initial.colorChoices = TaskListDefaults.colorChoices.map {
            ManageListsBehavior.ColorChoice(id: $0, color: Color(hexString: $0))
        }
        initial.selectedColorId = TaskListDefaults.colorChoices[0]
        initial.canAddLists = !membershipSession.isLapsed
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: ManageListsBehavior.ViewAction) async {
        switch action {
        case .load:
            await reload()

        case .draftNameChanged(let name):
            if let echo = lastCreatedDraftName, name == echo { return }
            lastCreatedDraftName = nil
            state.draftName = name
            state.canCreate = !name.trimmingCharacters(in: .whitespaces).isEmpty

        case .selectColor(let id):
            state.selectedColorId = id

        case .createTapped:
            guard uiState.canAddLists else { return }
            let name = uiState.draftName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let userId else { return }
            Haptics.success()
            // Optimistic: a re-fetch here can race the fire-and-forget
            // write and make the new list look like it was never created.
            if let created = try? await listRepository.createList(
                name: name,
                colorHex: uiState.selectedColorId,
                icon: TaskListDefaults.icon,
                order: (lists.map(\.order).max() ?? -1) + 1,
                userId: userId
            ) {
                lists.append(created)
                rebuildRows()
            }
            lastCreatedDraftName = uiState.draftName
            state.draftName = ""
            state.canCreate = false

        case .moveList(let from, let to):
            lists.move(fromOffsets: from, toOffset: to)
            rebuildRows()
            if let userId {
                try? await listRepository.saveOrder(ids: lists.map(\.id), userId: userId)
            }

        case .deleteTapped(let id):
            deleteCandidateId = id
            state.deleteCandidateName = lists.first { $0.id == id }?.name
            state.showDeleteConfirm = true

        case .confirmDelete:
            state.showDeleteConfirm = false
            guard let id = deleteCandidateId, let userId else { return }
            deleteCandidateId = nil
            lists.removeAll { $0.id == id }
            rebuildRows()
            try? await listRepository.deleteList(id: id, userId: userId)

        case .cancelDelete:
            deleteCandidateId = nil
            state.showDeleteConfirm = false

        case .renameTapped(let id):
            renameCandidateId = id
            state.renameDraft = lists.first { $0.id == id }?.name ?? ""
            state.showRename = true

        case .renameDraftChanged(let name):
            state.renameDraft = name

        case .confirmRename:
            state.showRename = false
            let name = uiState.renameDraft.trimmingCharacters(in: .whitespaces)
            guard let id = renameCandidateId, !name.isEmpty, let userId else { return }
            renameCandidateId = nil
            if let index = lists.firstIndex(where: { $0.id == id }) {
                lists[index].name = name
            }
            rebuildRows()
            try? await listRepository.renameList(id: id, name: name, userId: userId)

        case .cancelRename:
            renameCandidateId = nil
            state.showRename = false

        case .colorDotTapped(let id):
            state.editingColorListId = uiState.editingColorListId == id ? nil : id

        case .selectRowColor(let id, let colorHex):
            state.editingColorListId = nil
            guard let index = lists.firstIndex(where: { $0.id == id }), let userId else { return }
            lists[index].colorHex = colorHex
            rebuildRows()
            try? await listRepository.updateListColor(id: id, colorHex: colorHex, userId: userId)
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func reload() async {
        guard let userId else { return }
        lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        rebuildRows()
    }

    private func rebuildRows() {
        state.lists = lists.map {
            ManageListsBehavior.ListUIItem(
                id: $0.id,
                name: $0.name,
                icon: $0.icon,
                color: Color(hexString: $0.colorHex),
                colorHex: $0.colorHex
            )
        }
    }
}
