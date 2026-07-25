//
//  ManageRepeatingBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum ManageRepeatingBehavior {

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
        /// The pet's chosen name - construction sites that can't reach the
        /// pet identity keep the "Mochi" default.
        var petName = "Mochi"
        var series: [RepeatingUIItem] = []
        /// Series being edited - drives the task-editor sheet.
        var editingSeries: EditingSeries?
    }

    enum ViewAction {
        case load
        case seriesTapped(id: String)
        case seriesEditorDismissed
    }
}
