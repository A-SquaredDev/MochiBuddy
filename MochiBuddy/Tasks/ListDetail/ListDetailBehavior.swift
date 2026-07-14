//
//  ListDetailBehavior.swift
//  MochiBuddy
//

import SwiftUI

/// Which collection of tasks a ListDetail screen shows.
enum ListDetailSource: Equatable {
    case inbox
    case mochi(TaskList)
    /// A synced Apple Reminders list — read-only apart from check-offs.
    case reminders(listId: String, name: String, colorHex: String?)
}

enum ListDetailBehavior {

    struct UIState: UpdatableStruct, Equatable {
        /// True until the first fetch lands — drives the skeleton.
        var isLoading = true
        var title = ""
        var subtitle = ""      // "3 open · 5 done"
        var icon = "📥"
        var accent: Color = .clear
        var openItems: [TasksBehavior.TodoUIItem] = []
        var doneItems: [TasksBehavior.TodoUIItem] = []
        var showEmpty = false
        var canAdd = true
        /// New tasks born here land in this list (nil = Inbox).
        var newTaskListId: String?
        var editingTask: TasksBehavior.EditingTask?
    }

    enum ViewAction {
        case refresh
        case toggleTask(String)
        case taskTapped(String)
        case addTapped
        case editorDismissed
    }
}
