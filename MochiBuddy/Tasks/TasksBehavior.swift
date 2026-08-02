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
        var listName: String? = nil
        var listColor: Color? = nil
        var sourceBadge: String? = nil
        var isRecurring: Bool = false
        /// B4/B6: computed once per fetch by the Tasks/ListDetail VMs;
        /// Home builds its own item type and can never set this.
        var showsRetimeBadge: Bool = false
    }

    /// A labelled run of rows ("Overdue · 2", "Tomorrow · Wed", "Yesterday").
    struct Group: Equatable, Identifiable {
        let id: String
        let label: String
        let count: Int?
        let isDanger: Bool
        let items: [TodoUIItem]
        /// Done only: "JULY 2026" rendered above this group when the
        /// timeline crosses into an older month - the scroll reads as a
        /// dated archive without a separate screen.
        var monthHeader: String? = nil
    }

    struct ListUIItem: Equatable, Identifiable {
        let id: String
        let icon: String
        let name: String
        let countText: String
        let color: Color
        /// "Reminders" tag for externally-synced lists.
        var badge: String? = nil
    }

    /// Identifiable wrapper so the editor sheet presents via sheet(item:).
    struct EditingTask: Equatable, Identifiable {
        let task: TaskItem?
        var id: String { task?.id ?? "new" }
    }

    struct UIState: UpdatableStruct, Equatable {
        /// True until the first Firestore fetch lands - drives the skeleton.
        var isLoading = true
        /// The pet's chosen name - "Mochi" until the profile loads.
        var petName = "Mochi"
        /// Lapsed: existing tasks stay completable/editable, but new-task
        /// capture is removed ("Wake Mochi" lives on Home).
        var isLapsed = false
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
        /// Done only: an older page of history is available.
        var canLoadMoreDone = false
        /// Done only: the load-older request is in flight (shimmer rows).
        var isLoadingMoreDone = false
        /// Done only: the compact summary strip ("This week · N").
        var doneWeekText: String?
        /// Muted caption under the segment's content (Upcoming's explainer).
        var footnote: String?
        /// Upcoming only: entry point into the repeating-tasks screen.
        var showManageRepeating = false
        /// Lists only.
        var listItems: [ListUIItem] = []
        /// Lists only: shown when synced Reminders lists exist but access
        /// was revoked in Settings.
        var remindersAccessHint: String?
        var editingTask: EditingTask?
    }

    enum ViewAction {
        case refresh
        case selectSegment(Segment)
        case loadMoreDone
        case toggleTask(String)
        case taskTapped(String)
        case addTapped
        case editorDismissed
        case dismissCelebration
        case listTapped(String)
        case manageListsTapped
        case manageRepeatingTapped
    }

    enum NavigationEvent {
        case showManageLists
        case showManageRepeating
        case showListDetail(ListDetailSource)
    }
}
