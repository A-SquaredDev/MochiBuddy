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
        case skipTapped
    }

    enum NavigationEvent {
        /// Saved or skipped - either way the prompt is done and never
        /// returns for this device.
        case dismiss
    }
}
