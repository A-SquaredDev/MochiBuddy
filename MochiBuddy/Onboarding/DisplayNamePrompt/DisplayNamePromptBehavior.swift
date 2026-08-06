//
//  DisplayNamePromptBehavior.swift
//  MochiBuddy
//

import Foundation

enum DisplayNamePromptBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var draft = ""
        var canSave = false
        var isSaving = false
        /// The pet's name, so the ask is in the app's own voice rather than
        /// a generic "enter your name".
        var mochiName = "Mochi"
    }

    enum ViewAction {
        case draftChanged(String)
        case saveTapped
    }

    enum NavigationEvent {
        /// Saved - the only exit. The name is no longer empty, so the ask
        /// is closed structurally and never returns for this account.
        case dismiss
    }
}
