//
//  ListDetailViewModel.swift
//  MochiBuddy
//
//  One list's tasks - open up top, completed below. Check-offs route
//  through TaskCompletionStore, same as Home and the Tasks tab.
//

import SwiftUI

final class ListDetailViewModel: StateViewModel<
    ListDetailBehavior.UIState,
    ListDetailBehavior.ViewAction
> {

    private let source: ListDetailSource
    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository
    private let profileRepository: UserProfileRepository
    private let completionStore: TaskCompletionStore
    private let remindersGateway: RemindersGateway
    private let membershipSession: MembershipSession
    private let recurrenceRoller: RecurrenceRoller
    private let relay: NotificationRelaying
    private let suggestionService: SuggestionService?

    // Domain source of truth - UIState is derived from these.
    private var open: [TaskItem] = []
    /// Re-time badge ids, computed once per fetch (guide B4).
    private var retimeBadgeIds: Set<String> = []
    private var done: [TaskItem] = []
    private var reminders: [ReminderTaskItem] = []
    private var coins = 0

    init(
        source: ListDetailSource,
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        profileRepository: UserProfileRepository,
        completionStore: TaskCompletionStore,
        remindersGateway: RemindersGateway,
        membershipSession: MembershipSession,
        recurrenceRoller: RecurrenceRoller,
        relay: NotificationRelaying,
        suggestionService: SuggestionService? = nil
    ) {
        self.source = source
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.profileRepository = profileRepository
        self.completionStore = completionStore
        self.remindersGateway = remindersGateway
        self.membershipSession = membershipSession
        self.recurrenceRoller = recurrenceRoller
        self.relay = relay
        self.suggestionService = suggestionService

        var initial = ListDetailBehavior.UIState()
        switch source {
        case .inbox:
            initial.title = "Inbox"
            initial.icon = "tray.fill"
            initial.accent = Color(hexString: TaskListDefaults.colorChoices[0])
            initial.newTaskListId = nil
        case .mochi(let list):
            initial.title = list.name
            initial.icon = list.icon
            initial.accent = Color(hexString: list.colorHex)
            initial.newTaskListId = list.id
        case .reminders(_, let name, let colorHex):
            initial.title = name
            initial.icon = "checklist"
            initial.accent = Color(hexString: colorHex ?? TaskListDefaults.colorChoices[0])
            // New tasks can't be written into Apple Reminders; completed
            // reminders stay in the Reminders app, not here.
            initial.canAdd = false
        }
        // Lapsed: existing tasks stay completable, new capture is removed.
        if membershipSession.isLapsed {
            initial.canAdd = false
        }
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: ListDetailBehavior.ViewAction) async {
        switch action {
        case .refresh:
            await refresh()

        case .toggleTask(let id):
            await toggleTask(id: id)

        case .taskTapped(let id):
            // Reminder rows have no editor - they're managed in Apple Reminders.
            if case .reminders = source { return }
            if let task = (open + done).first(where: { $0.id == id }) {
                state.editingTask = TasksBehavior.EditingTask(task: task)
            }

        case .addTapped:
            guard uiState.canAdd else { return }
            state.editingTask = TasksBehavior.EditingTask(task: nil)

        case .editorDismissed:
            state.editingTask = nil
            await refresh()
            relay.requestRelay(.taskChange)
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    /// nil means the implicit Inbox (tasks without a listId).
    private var listId: String? {
        switch source {
        case .inbox: nil
        case .mochi(let list): list.id
        case .reminders(let listId, _, _): listId
        }
    }

    private func refresh() async {
        defer { state.isLoading = false }

        if case .reminders(let reminderListId, _, _) = source {
            reminders = await remindersGateway.fetchOpenReminders(listIds: [reminderListId])
            rebuild()
            return
        }

        guard let userId else { return }
        let scopedListId = listId
        var fetched = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        // Roll before filtering so a re-stamped occurrence keeps this list
        // consistent with Home and the Tasks tab.
        let profile = try? await profileRepository.fetchProfile(userId: userId)
        fetched = await recurrenceRoller.rollForward(
            fetched,
            frozen: (profile?.vacationActive(at: .now) ?? false) || membershipSession.isLapsed,
            userId: userId
        )
        open = fetched.filter { $0.listId == scopedListId }
        // A real list gets its OWN recent completions (guide D6) so other
        // lists' activity can never starve this section. The scoped query
        // needs the console composite index (listId ASC, completedAt DESC);
        // until it exists, or for the Inbox (no indexable predicate for a
        // missing field), fall back to filtering the global page.
        if let scopedListId,
           let scoped = try? await taskRepository.completedTasks(
               listId: scopedListId, limit: 20, userId: userId
           ) {
            done = scoped
        } else {
            done = ((try? await taskRepository.completedTasks(limit: 50, userId: userId)) ?? [])
                .filter { $0.listId == scopedListId }
        }
        coins = profile?.coins ?? coins
        retimeBadgeIds = await suggestionService?.retimeBadgeTaskIds(tasks: open) ?? []
        rebuild()
    }

    private func toggleTask(id: String) async {
        if case .reminders = source {
            await toggleReminder(id: id)
            return
        }
        guard let userId else { return }
        let nowCompleted: Bool
        let task: TaskItem

        if let index = open.firstIndex(where: { $0.id == id }) {
            task = open[index]
            nowCompleted = true
            open[index].completed = true
            open[index].completedAt = .now
            done.insert(open[index], at: 0)
            open.remove(at: index)
            Haptics.success()
        } else if let index = done.firstIndex(where: { $0.id == id }) {
            task = done[index]
            nowCompleted = false
            done[index].completed = false
            done[index].completedAt = nil
            open.append(done[index])
            done.remove(at: index)
        } else {
            return
        }

        rebuild()
        let outcome = await completionStore.setCompleted(
            task, completed: nowCompleted, currentCoins: coins, userId: userId
        )
        coins += outcome.coinsDelta
        if let spawned = outcome.spawnedNext, spawned.listId == listId {
            open.append(spawned)
        }
        if let reaped = outcome.reapedTaskId {
            open.removeAll { $0.id == reaped }
        }
        rebuild()
    }

    /// No coins, no streak, no editor - completion just writes back to
    /// EventKit, reverting the optimistic flip if the save fails.
    private func toggleReminder(id: String) async {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let nowCompleted = !reminders[index].completed
        reminders[index].completed = nowCompleted
        if nowCompleted { Haptics.success() }
        rebuild()

        let saved = await remindersGateway.setReminderCompleted(id: id, completed: nowCompleted)
        if !saved {
            if let revertIndex = reminders.firstIndex(where: { $0.id == id }) {
                reminders[revertIndex].completed = !nowCompleted
            }
            rebuild()
        }
    }

    // MARK: - Derivation

    private func rebuild() {
        if case .reminders = source {
            rebuildReminders()
            return
        }
        let now = Date.now
        var next = uiState
        let sortedOpen = open.sorted {
            ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
        }
        let sortedDone = done.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
        next.openItems = sortedOpen.map { item(for: $0, now: now) }
        next.doneItems = sortedDone.map { item(for: $0, now: now) }
        next.subtitle = "\(open.count) open · \(done.count) done"
        next.showEmpty = open.isEmpty && done.isEmpty
        setUIState(next)
    }

    private func rebuildReminders() {
        let now = Date.now
        var next = uiState
        let openReminders = reminders.filter { !$0.completed }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let doneReminders = reminders.filter(\.completed)
        next.openItems = openReminders.map { reminderItem($0, now: now) }
        next.doneItems = doneReminders.map { reminderItem($0, now: now) }
        next.subtitle = "\(openReminders.count) open · completed ones stay in Apple Reminders"
        next.showEmpty = reminders.isEmpty
        setUIState(next)
    }

    private func reminderItem(_ reminder: ReminderTaskItem, now: Date) -> TasksBehavior.TodoUIItem {
        let display = TodoItemDisplay.row(
            completed: reminder.completed,
            completedAt: nil,
            dueAt: reminder.dueAt,
            hasTime: reminder.hasTime,
            priority: nil,
            now: now
        )
        return TasksBehavior.TodoUIItem(
            id: reminder.id, title: reminder.title,
            meta: display.meta, state: display.state, chip: display.chip,
            sourceBadge: "Reminders"
        )
    }

    private func item(for task: TaskItem, now: Date) -> TasksBehavior.TodoUIItem {
        let display = TodoItemDisplay.row(for: task, now: now)
        // No list indicator here - every row belongs to this screen's list.
        return TasksBehavior.TodoUIItem(
            id: task.id, title: task.title,
            meta: display.meta, state: display.state, chip: display.chip,
            isRecurring: task.repeatRule != nil,
            showsRetimeBadge: retimeBadgeIds.contains(task.id)
        )
    }
}
