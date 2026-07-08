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
    }

    struct ColorChoice: Equatable, Identifiable {
        let id: String   // the hex string
        let color: Color
    }

    struct UIState: UpdatableStruct, Equatable {
        var lists: [ListUIItem] = []
        var colorChoices: [ColorChoice] = []
        var selectedColorId = ""
        var draftName = ""
        var canCreate = false
        /// List pending deletion — drives the confirm alert.
        var deleteCandidateName: String?
        var showDeleteConfirm = false
        /// List being renamed — drives the rename alert.
        var renameDraft = ""
        var showRename = false
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
    }
}
