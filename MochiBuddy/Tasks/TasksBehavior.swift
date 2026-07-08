//
//  TasksBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum TasksBehavior {

    enum Segment: String, CaseIterable {
        case today = "Today"
        case upcoming = "Upcoming"
        case lists = "Lists"
        case done = "Done"
    }

    struct TodoUIItem: Equatable, Identifiable {
        let id: String
        let title: String
        let meta: String
        let state: TodoRowState
        let chip: String
    }

    /// A labelled run of rows ("Overdue · 2", "Tomorrow · Wed", "Yesterday").
    struct Group: Equatable, Identifiable {
        let id: String
        let label: String
        let count: Int?
        let isDanger: Bool
        let items: [TodoUIItem]
    }

    struct ListUIItem: Equatable, Identifiable {
        let id: String
        let icon: String
        let name: String
        let countText: String
        let color: Color
    }

    /// Identifiable wrapper so the editor sheet presents via sheet(item:).
    struct EditingTask: Equatable, Identifiable {
        let task: TaskItem?
        var id: String { task?.id ?? "new" }
    }

    struct UIState: UpdatableStruct, Equatable {
        var segment: Segment = .today
        var subtitle = ""
        var coins = 0
        var groups: [Group] = []
        /// Today only: calm empty vs. celebration.
        var showEmptyCalm = false
        var showAllCaughtUp = false
        var streakDays = 0
        /// Done only: the coins-earned celebration card.
        var doneCelebration: String?
        /// Lists only.
        var listItems: [ListUIItem] = []
        var editingTask: EditingTask?
    }

    enum ViewAction {
        case refresh
        case selectSegment(Segment)
        case toggleTask(String)
        case taskTapped(String)
        case addTapped
        case editorDismissed
        case manageListsTapped
    }

    enum NavigationEvent {
        case showManageLists
    }
}
