//
//  ManageListsBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum ManageListsBehavior {

    struct ListUIItem: Equatable, Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let colorHex: String
    }

    struct ColorChoice: Equatable, Identifiable {
        let id: String   // the hex string
        let color: Color
    }

    /// One recurring series (a live task carrying a repeat rule).
    struct RepeatingUIItem: Equatable, Identifiable {
        let id: String
        let title: String
        let cadence: String
    }

    /// Sheet payload for editing a series via the task editor.
    struct EditingSeries: Equatable, Identifiable {
        let task: TaskItem
        var id: String { task.id }
    }

    struct UIState: UpdatableStruct, Equatable {
        var lists: [ListUIItem] = []
        var colorChoices: [ColorChoice] = []
        var selectedColorId = ""
        var draftName = ""
        var canCreate = false
        /// Lapsed: no new lists - the whole New-list section hides.
        var canAddLists = true
        /// List pending deletion - drives the confirm alert.
        var deleteCandidateName: String?
        var showDeleteConfirm = false
        /// List being renamed - drives the rename alert.
        var renameDraft = ""
        var showRename = false
        /// List whose color swatches are expanded inline (nil = none).
        var editingColorListId: String?
        /// Live recurring series, shown in their own section.
        var repeating: [RepeatingUIItem] = []
        /// Series being edited - drives the task-editor sheet.
        var editingSeries: EditingSeries?
    }

    enum ViewAction {
        case load
        case draftNameChanged(String)
        case selectColor(String)
        case createTapped
        case moveList(from: IndexSet, to: Int)
        case deleteTapped(id: String)
        case confirmDelete
        case cancelDelete
        case renameTapped(id: String)
        case renameDraftChanged(String)
        case confirmRename
        case cancelRename
        case colorDotTapped(id: String)
        case selectRowColor(id: String, colorHex: String)
        case seriesTapped(id: String)
        case seriesEditorDismissed
    }
}
