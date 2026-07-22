//
//  TasksViewModel.swift
//  MochiBuddy
//
//  The Tasks tab - Today (overdue pinned up top), Upcoming (grouped by
//  day), Lists (categories overview), Done (with coins earned). Check-offs
//  route through TaskCompletionStore, same as Home.
//

import SwiftUI

final class TasksViewModel: ObservableStateViewModel<
    TasksBehavior.UIState,
    TasksBehavior.ViewAction,
    TasksBehavior.NavigationEvent
> {

    private static let celebrationDismissedDayKey = "mochi.doneCelebrationDismissedDay"

    /// Reminder-backed rows carry this id prefix so actions can route to
    /// EventKit instead of Firestore.
    static let reminderIdPrefix = "ek:"

    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let profileRepository: UserProfileRepository
    private let completionStore: TaskCompletionStore
    private let remindersGateway: RemindersGateway
    private let membershipSession: MembershipSession
    private let recurrenceRoller: RecurrenceRoller
    private let relay: NotificationRelaying
    private let defaults: UserDefaults

    // Domain source of truth - UIState is derived from these.
    private var incomplete: [TaskItem] = []
    private var completed: [TaskItem] = []
    private var lists: [TaskList] = []
    private var reminders: [ReminderTaskItem] = []
    private var reminderLists: [ReminderList] = []
    private var remindersBlocked = false
    private var coins = 0
    private var streak = 0

    init(
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        profileRepository: UserProfileRepository,
        completionStore: TaskCompletionStore,
        remindersGateway: RemindersGateway,
        membershipSession: MembershipSession,
        recurrenceRoller: RecurrenceRoller,
        relay: NotificationRelaying,
        defaults: UserDefaults = .standard
    ) {
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.profileRepository = profileRepository
        self.completionStore = completionStore
        self.remindersGateway = remindersGateway
        self.membershipSession = membershipSession
        self.recurrenceRoller = recurrenceRoller
        self.relay = relay
        self.defaults = defaults
        super.init(initialState: TasksBehavior.UIState())
    }

    override func triggerAsync(_ action: TasksBehavior.ViewAction) async {
        switch action {
        case .refresh:
            await refresh()

        case .selectSegment(let segment):
            state.segment = segment
            rebuild()

        case .toggleTask(let id):
            await toggleTask(id: id)

        case .taskTapped(let id):
            // Reminder rows have no editor - they're managed in Apple Reminders.
            guard !id.hasPrefix(Self.reminderIdPrefix) else { return }
            let all = incomplete + completed
            if let task = all.first(where: { $0.id == id }) {
                state.editingTask = TasksBehavior.EditingTask(task: task)
            }

        case .addTapped:
            // Lapsed: no new tasks - the add affordances are hidden, this
            // guard covers any path that still fires the action.
            guard !uiState.isLapsed else { return }
            state.editingTask = TasksBehavior.EditingTask(task: nil)

        case .editorDismissed:
            state.editingTask = nil
            await refresh()
            relay.requestRelay(.taskChange)

        case .dismissCelebration:
            defaults.set(Self.dayKey(for: .now), forKey: Self.celebrationDismissedDayKey)
            state.doneCelebration = nil

        case .listTapped(let id):
            if id == "inbox" {
                setNavigationEvent(.showListDetail(.inbox))
            } else if id.hasPrefix(Self.reminderIdPrefix) {
                let reminderListId = String(id.dropFirst(Self.reminderIdPrefix.count))
                if let list = reminderLists.first(where: { $0.id == reminderListId }) {
                    setNavigationEvent(.showListDetail(
                        .reminders(listId: list.id, name: list.name, colorHex: list.colorHex)
                    ))
                }
            } else if let list = lists.first(where: { $0.id == id }) {
                setNavigationEvent(.showListDetail(.mochi(list)))
            }

        case .manageListsTapped:
            setNavigationEvent(.showManageLists)
        }
    }

    /// "2026-07-14" - dismissal is per-day so the banner returns tomorrow.
    private static func dayKey(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func refresh() async {
        defer { state.isLoading = false }
        guard let userId else { return }
        incomplete = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        completed = (try? await taskRepository.completedTasks(limit: 50, userId: userId)) ?? []
        lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        var syncedReminderListIds: [String] = []
        var onVacation = false
        if let profile = try? await profileRepository.fetchProfile(userId: userId) {
            coins = profile.coins
            streak = profile.streakCount
            syncedReminderListIds = profile.importedReminderListIds
            onVacation = profile.vacationActive(at: .now)
        }
        // One-live-occurrence invariant - same roll Home applies, so the
        // two surfaces can never disagree on a recurring task's due date.
        incomplete = await recurrenceRoller.rollForward(
            incomplete,
            frozen: onVacation || membershipSession.isLapsed,
            userId: userId
        )
        state.isLapsed = membershipSession.isLapsed
        await refreshReminders(syncedListIds: syncedReminderListIds)
        rebuild()
    }

    /// Access can flip in Settings mid-session - re-check every refresh.
    private func refreshReminders(syncedListIds: [String]) async {
        guard !syncedListIds.isEmpty else {
            (reminders, reminderLists, remindersBlocked) = ([], [], false)
            return
        }
        guard remindersGateway.accessStatus == .granted else {
            (reminders, reminderLists) = ([], [])
            remindersBlocked = true
            return
        }
        remindersBlocked = false
        reminderLists = await remindersGateway.fetchLists()
            .filter { syncedListIds.contains($0.id) }
        reminders = await remindersGateway.fetchOpenReminders(listIds: syncedListIds)
    }

    private func toggleTask(id: String) async {
        guard let userId else { return }
        if id.hasPrefix(Self.reminderIdPrefix) {
            await toggleReminder(id: String(id.dropFirst(Self.reminderIdPrefix.count)))
            return
        }
        let nowCompleted: Bool
        let task: TaskItem

        if let index = incomplete.firstIndex(where: { $0.id == id }) {
            task = incomplete[index]
            nowCompleted = true
            incomplete[index].completed = true
            incomplete[index].completedAt = .now
            completed.insert(incomplete[index], at: 0)
            incomplete.remove(at: index)
            Haptics.success()
        } else if let index = completed.firstIndex(where: { $0.id == id }) {
            task = completed[index]
            nowCompleted = false
            completed[index].completed = false
            completed[index].completedAt = nil
            incomplete.append(completed[index])
            completed.remove(at: index)
        } else {
            return
        }

        rebuild()
        let outcome = await completionStore.setCompleted(
            task, completed: nowCompleted, currentCoins: coins, userId: userId
        )
        coins += outcome.coinsDelta
        if let newStreak = outcome.streak {
            streak = newStreak
        }
        if let spawned = outcome.spawnedNext {
            incomplete.append(spawned)
        }
        if let reaped = outcome.reapedTaskId {
            incomplete.removeAll { $0.id == reaped }
        }
        rebuild()
    }

    /// Reminder check-offs write back to Apple Reminders only - no coins,
    /// no streak, no repeat-spawning. Reverts the flip if the save fails.
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
        let now = Date.now
        var next = uiState
        next.coins = coins
        next.streakDays = streak
        next.showEmptyCalm = false
        next.showAllCaughtUp = false
        next.doneCelebration = nil
        next.footnote = nil
        next.listItems = []
        next.groups = []
        next.remindersAccessHint = remindersBlocked
            ? "Reminders access is off. Re-enable it in Settings to see your synced lists."
            : nil

        // Firestore completions only - reminder check-offs earn no coins,
        // so they must never feed the celebration math.
        let doneToday = completed.filter {
            $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false
        }
        // Reminder rows ride the same pipelines as pseudo-tasks.
        let openReminderTasks = reminders.filter { !$0.completed }.map(reminderPseudoTask)
        let doneReminderTasks = reminders.filter(\.completed).map(reminderPseudoTask)

        switch uiState.segment {
        case .today:
            next.subtitle = now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let open = incomplete + openReminderTasks
            let overdue = open
                .filter { (MoodEngine.hoursOverdue($0, now: now) ?? -1) > 0 }
                .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
            let today = open
                .filter { task in
                    guard let dueAt = task.dueAt else { return false }
                    return Calendar.current.isDate(dueAt, inSameDayAs: now)
                        && (MoodEngine.hoursOverdue(task, now: now) ?? 0) <= 0
                }
                .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
            let doneTodayRows = doneToday + doneReminderTasks

            if overdue.isEmpty, today.isEmpty {
                next.showAllCaughtUp = !doneTodayRows.isEmpty
                next.showEmptyCalm = doneTodayRows.isEmpty
            } else {
                if !overdue.isEmpty {
                    next.groups.append(group("overdue", "Overdue", overdue, danger: true, now: now))
                }
                next.groups.append(group("today", "Today", today, now: now))
            }
            if !doneTodayRows.isEmpty {
                next.groups.append(group("doneToday", "Completed today", doneTodayRows, now: now))
            }

        case .upcoming:
            next.subtitle = "Next 7 days"
            next.groups = upcomingGroups(over: incomplete + openReminderTasks, now: now)
            next.footnote = "All future-dated tasks live here. No date means Someday, "
                + "beyond 7 days means Later. Repeating tasks appear once their "
                + "next occurrence is scheduled."

        case .lists:
            next.subtitle = "Your categories"
            next.listItems = listRows()

        case .done:
            let doneThisWeek = completed.filter {
                $0.completedAt.map { $0 > now.addingTimeInterval(-7 * 24 * 3600) } ?? false
            }.count
            next.subtitle = "\(doneThisWeek) done this week"
            // Honest math (today's completions × the flat per-task rate) and
            // per-day dismissible - never a running total of stale history.
            let dismissedToday = defaults.string(forKey: Self.celebrationDismissedDayKey) == Self.dayKey(for: now)
            if !doneToday.isEmpty, !dismissedToday {
                next.doneCelebration = "Earned +\(doneToday.count * RewardsStore.coinsPerTask) coins today"
            }
            next.groups = doneGroups(now: now)
        }

        setUIState(next)
    }

    private func group(
        _ id: String,
        _ label: String,
        _ tasks: [TaskItem],
        danger: Bool = false,
        now: Date
    ) -> TasksBehavior.Group {
        TasksBehavior.Group(
            id: id,
            label: label,
            count: tasks.count,
            isDanger: danger,
            items: tasks.map { item(for: $0, now: now) }
        )
    }

    private func upcomingGroups(over tasks: [TaskItem], now: Date) -> [TasksBehavior.Group] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var byOffset: [Int: [TaskItem]] = [:]
        var later: [TaskItem] = []
        var someday: [TaskItem] = []

        for task in tasks {
            guard let dueAt = task.dueAt else {
                someday.append(task)
                continue
            }
            let due = calendar.startOfDay(for: dueAt)
            let offset = calendar.dateComponents([.day], from: today, to: due).day ?? 0
            if offset <= 0 { continue } // today/overdue live in the Today segment
            if offset <= 6 {
                byOffset[offset, default: []].append(task)
            } else {
                later.append(task)
            }
        }

        var groups: [TasksBehavior.Group] = []
        for offset in 1...6 {
            guard let tasks = byOffset[offset], !tasks.isEmpty else { continue }
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let weekday = day.formatted(.dateTime.weekday(offset == 1 ? .abbreviated : .wide))
            let label = offset == 1 ? "Tomorrow · \(weekday)" : weekday
            groups.append(group("d\(offset)", label, tasks.sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }, now: now))
        }
        if !later.isEmpty {
            groups.append(group("later", "Later", later.sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }, now: now))
        }
        if !someday.isEmpty {
            groups.append(group("someday", "Someday", someday, now: now))
        }
        return groups
    }

    /// One group per calendar day, newest first - the Done tab renders these
    /// as a dated timeline. Fetch is capped at the 50 newest completions, so
    /// the oldest day may be partial.
    private func doneGroups(now: Date) -> [TasksBehavior.Group] {
        let calendar = Calendar.current
        var byDay: [Date: [TaskItem]] = [:]
        var undated: [TaskItem] = []
        for task in completed {
            guard let completedAt = task.completedAt else {
                undated.append(task)
                continue
            }
            byDay[calendar.startOfDay(for: completedAt), default: []].append(task)
        }

        var groups: [TasksBehavior.Group] = byDay.keys.sorted(by: >).map { day in
            let label: String
            if calendar.isDateInToday(day) {
                label = "Today"
            } else if calendar.isDateInYesterday(day) {
                label = "Yesterday"
            } else {
                label = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            let tasks = byDay[day]!.sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            return group(Self.dayKey(for: day), label, tasks, now: now)
        }
        if !undated.isEmpty {
            groups.append(group("earlier", "Earlier", undated, now: now))
        }
        return groups
    }

    private func listRows() -> [TasksBehavior.ListUIItem] {
        var countByList: [String?: Int] = [:]
        for task in incomplete {
            countByList[task.listId, default: 0] += 1
        }
        func countText(_ count: Int) -> String {
            "\(count) open task\(count == 1 ? "" : "s")"
        }
        var rows = [TasksBehavior.ListUIItem(
            id: "inbox",
            icon: "tray.fill",
            name: "Inbox",
            countText: countText(countByList[nil] ?? 0),
            color: Color(hexString: TaskListDefaults.colorChoices[0])
        )]
        rows += lists.map { list in
            TasksBehavior.ListUIItem(
                id: list.id,
                icon: list.icon,
                name: list.name,
                countText: countText(countByList[list.id] ?? 0),
                color: Color(hexString: list.colorHex)
            )
        }
        rows += reminderLists.map { list in
            let openCount = reminders.filter { $0.listId == list.id && !$0.completed }.count
            return TasksBehavior.ListUIItem(
                id: Self.reminderIdPrefix + list.id,
                icon: "checklist",
                name: list.name,
                countText: countText(openCount),
                color: list.colorHex.map { Color(hexString: $0) }
                    ?? Color(hexString: TaskListDefaults.colorChoices[0]),
                badge: "Reminders"
            )
        }
        return rows
    }

    /// Reminder-backed rows dressed as tasks so grouping/sorting reuse the
    /// task pipelines. They never touch Firestore - actions route by prefix.
    private func reminderPseudoTask(_ reminder: ReminderTaskItem) -> TaskItem {
        TaskItem(
            id: Self.reminderIdPrefix + reminder.id,
            title: reminder.title, notes: nil,
            dueAt: reminder.dueAt, hasTime: reminder.hasTime,
            priority: .med,
            listId: Self.reminderIdPrefix + reminder.listId,
            repeatRule: nil,
            completed: reminder.completed,
            completedAt: nil,
            createdAt: nil
        )
    }

    private func item(for task: TaskItem, now: Date) -> TasksBehavior.TodoUIItem {
        let display = TodoItemDisplay.row(for: task, now: now)

        if task.id.hasPrefix(Self.reminderIdPrefix) {
            let reminderListId = String((task.listId ?? "").dropFirst(Self.reminderIdPrefix.count))
            let list = reminderLists.first { $0.id == reminderListId }
            return TasksBehavior.TodoUIItem(
                id: task.id, title: task.title,
                meta: display.meta, state: display.state, chip: display.chip,
                listName: list?.name,
                listColor: list?.colorHex.map { Color(hexString: $0) },
                sourceBadge: "Reminders"
            )
        }

        let listTag = TodoItemDisplay.listTag(for: task.listId, in: lists)
        return TasksBehavior.TodoUIItem(
            id: task.id, title: task.title,
            meta: display.meta, state: display.state, chip: display.chip,
            listName: listTag?.name,
            listColor: listTag?.color,
            isRecurring: task.repeatRule != nil
        )
    }
}
