//
//  TasksViewModel.swift
//  MochiBuddy
//
//  The Tasks tab — Today (overdue pinned up top), Upcoming (grouped by
//  day), Lists (categories overview), Done (with coins earned). Check-offs
//  route through TaskCompletionStore, same as Home.
//

import SwiftUI

final class TasksViewModel: ObservableStateViewModel<
    TasksBehavior.UIState,
    TasksBehavior.ViewAction,
    TasksBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let profileRepository: UserProfileRepository
    private let completionStore: TaskCompletionStore

    // Domain source of truth — UIState is derived from these.
    private var incomplete: [TaskItem] = []
    private var completed: [TaskItem] = []
    private var lists: [TaskList] = []
    private var coins = 0
    private var streak = 0

    init(
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        profileRepository: UserProfileRepository,
        completionStore: TaskCompletionStore
    ) {
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.profileRepository = profileRepository
        self.completionStore = completionStore
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
            let all = incomplete + completed
            if let task = all.first(where: { $0.id == id }) {
                state.editingTask = TasksBehavior.EditingTask(task: task)
            }

        case .addTapped:
            state.editingTask = TasksBehavior.EditingTask(task: nil)

        case .editorDismissed:
            state.editingTask = nil
            await refresh()

        case .manageListsTapped:
            setNavigationEvent(.showManageLists)
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func refresh() async {
        guard let userId else { return }
        incomplete = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        completed = (try? await taskRepository.completedTasks(limit: 50, userId: userId)) ?? []
        lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        if let profile = try? await profileRepository.fetchProfile(userId: userId) {
            coins = profile.coins
            streak = profile.streakCount
        }
        rebuild()
    }

    private func toggleTask(id: String) async {
        guard let userId else { return }
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
        rebuild()
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
        next.listItems = []
        next.groups = []

        switch uiState.segment {
        case .today:
            next.subtitle = now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let overdue = incomplete
                .filter { (MoodEngine.hoursOverdue($0, now: now) ?? -1) > 0 }
                .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
            let today = incomplete
                .filter { task in
                    guard let dueAt = task.dueAt else { return false }
                    return Calendar.current.isDate(dueAt, inSameDayAs: now)
                        && (MoodEngine.hoursOverdue(task, now: now) ?? 0) <= 0
                }
                .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }

            if overdue.isEmpty, today.isEmpty {
                let doneToday = completed.contains {
                    $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false
                }
                next.showAllCaughtUp = doneToday
                next.showEmptyCalm = !doneToday
            } else {
                if !overdue.isEmpty {
                    next.groups.append(group("overdue", "Overdue", overdue, danger: true, now: now))
                }
                next.groups.append(group("today", "Today", today, now: now))
            }

        case .upcoming:
            next.subtitle = "Next 7 days"
            next.groups = upcomingGroups(now: now)

        case .lists:
            next.subtitle = "Your categories"
            next.listItems = listRows()

        case .done:
            let doneThisWeek = completed.filter {
                $0.completedAt.map { $0 > now.addingTimeInterval(-7 * 24 * 3600) } ?? false
            }.count
            next.subtitle = "\(doneThisWeek) done this week"
            if !completed.isEmpty {
                next.doneCelebration = "Earned +\(completed.count * RewardsStore.coinsPerTask) coins from these"
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

    private func upcomingGroups(now: Date) -> [TasksBehavior.Group] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var byOffset: [Int: [TaskItem]] = [:]
        var later: [TaskItem] = []
        var someday: [TaskItem] = []

        for task in incomplete {
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

    private func doneGroups(now: Date) -> [TasksBehavior.Group] {
        let calendar = Calendar.current
        var todayTasks: [TaskItem] = []
        var yesterdayTasks: [TaskItem] = []
        var earlier: [TaskItem] = []
        for task in completed {
            guard let completedAt = task.completedAt else {
                earlier.append(task)
                continue
            }
            if calendar.isDateInToday(completedAt) {
                todayTasks.append(task)
            } else if calendar.isDateInYesterday(completedAt) {
                yesterdayTasks.append(task)
            } else {
                earlier.append(task)
            }
        }
        var groups: [TasksBehavior.Group] = []
        if !todayTasks.isEmpty { groups.append(group("today", "Today", todayTasks, now: now)) }
        if !yesterdayTasks.isEmpty { groups.append(group("yesterday", "Yesterday", yesterdayTasks, now: now)) }
        if !earlier.isEmpty { groups.append(group("earlier", "Earlier", earlier, now: now)) }
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
            icon: "📥",
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
        return rows
    }

    private func item(for task: TaskItem, now: Date) -> TasksBehavior.TodoUIItem {
        let state: TodoRowState
        let meta: String

        if task.completed {
            state = .done
            meta = task.completedAt.map { "Done · \(Self.doneText($0, now: now))" } ?? "Done · nice one"
        } else if let hours = MoodEngine.hoursOverdue(task, now: now), hours > 0 {
            state = .overdue
            meta = "⏰ Overdue by \(Self.overdueText(hours: hours))"
        } else if let dueAt = task.dueAt {
            let calendar = Calendar.current
            let timeText = dueAt.formatted(date: .omitted, time: .shortened)
            if calendar.isDate(dueAt, inSameDayAs: now) {
                if task.hasTime, dueAt.timeIntervalSince(now) < 3 * 3600 {
                    state = .due
                    meta = "Due soon · \(timeText)"
                } else {
                    state = .normal
                    meta = task.hasTime ? "Due today · \(timeText)" : "Due later today"
                }
            } else {
                state = .normal
                let dayText = dueAt.formatted(.dateTime.weekday(.abbreviated))
                meta = task.hasTime ? "\(dayText) · \(timeText)" : "\(dayText) · all day"
            }
        } else {
            state = .normal
            meta = "Anytime"
        }

        let chip = switch state {
        case .done: "Done"
        case .due: "Soon"
        case .overdue, .normal: task.priority == .high ? "High" : "Focus"
        }

        return TasksBehavior.TodoUIItem(id: task.id, title: task.title, meta: meta, state: state, chip: chip)
    }

    private static func doneText(_ completedAt: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(completedAt) { return "nice one" }
        if calendar.isDateInYesterday(completedAt) { return "yesterday" }
        return completedAt.formatted(.dateTime.day().month(.abbreviated))
    }

    private static func overdueText(hours: Double) -> String {
        if hours < 1 { return "a moment" }
        if hours < 24 { return "\(Int(hours)) hr" }
        let days = Int(hours / 24)
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}
