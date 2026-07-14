//
//  HomeViewModel.swift
//  MochiBuddy
//
//  Home — the core loop on one screen: Mochi's mood tracks the task list,
//  completing tasks earns coins, pets/treats buy temporary comfort. The
//  baseline comes from MoodEngine; the buffer decays via a 30s tick.
//

import SwiftUI
import Combine

final class HomeViewModel: StateViewModel<
    HomeBehavior.UIState,
    HomeBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let bufferStore: ComfortBufferStore
    private let rewardsStore: RewardsStore
    private let completionStore: TaskCompletionStore

    // Domain source of truth — UIState is derived from these.
    /// Incomplete tasks only; completions move to `completedToday`.
    private var tasks: [TaskItem] = []
    private var completedToday: [TaskItem] = []
    private var lists: [TaskList] = []
    private var completionsLast24h = 0
    private var vacationMode = false
    private var bedtime: BedtimeWindow = .standard
    private var coins = 0
    private var streak = 0
    private var hasStartedTimer = false
    /// After submit clears the field, a focused TextField can echo one last
    /// `.quickAddChanged` with the submitted title (autocorrect committing on
    /// return) and resurrect the text — swallow exactly that one echo.
    private var lastSubmittedQuickAddTitle: String?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        bufferStore: ComfortBufferStore,
        rewardsStore: RewardsStore,
        completionStore: TaskCompletionStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.bufferStore = bufferStore
        self.rewardsStore = rewardsStore
        self.completionStore = completionStore
        super.init(initialState: HomeBehavior.UIState())
    }

    override func triggerAsync(_ action: HomeBehavior.ViewAction) async {
        switch action {
        case .refresh:
            startTimerIfNeeded()
            await refresh()

        case .tick:
            rebuildDerivedState()

        case .petTapped:
            bufferStore.add(lift: TreatCatalog.Pet.lift, duration: TreatCatalog.Pet.duration)
            Haptics.impact(.soft)
            state.petSquishTrigger += 1
            rebuildDerivedState()

        case .treatsTapped:
            Haptics.impact(.light)
            state.showTreats = true

        case .dismissTreats:
            state.showTreats = false

        case .giveTreat(let id):
            await giveTreat(id: id)

        case .quickAddChanged(let text):
            // The field can echo the submitted title more than once (focus
            // resign + autocorrect commit + sheet presentation), so keep
            // swallowing that exact string until different input arrives.
            if let echo = lastSubmittedQuickAddTitle, text == echo { return }
            lastSubmittedQuickAddTitle = nil
            state.quickAddText = text

        case .quickAddSubmitted:
            await quickAdd()

        case .composeTapped:
            let title = uiState.quickAddText.trimmingCharacters(in: .whitespaces)
            if !uiState.quickAddText.isEmpty {
                lastSubmittedQuickAddTitle = uiState.quickAddText
                state.quickAddText = ""
            }
            Haptics.impact(.light)
            state.editingTask = HomeBehavior.EditingTask(
                task: nil,
                draftTitle: title.isEmpty ? nil : title
            )

        case .toggleTask(let id):
            await toggleTask(id: id)

        case .taskTapped(let id):
            if let task = (tasks + completedToday).first(where: { $0.id == id }) {
                state.editingTask = HomeBehavior.EditingTask(task: task)
            }

        case .editorDismissed:
            state.editingTask = nil
            await refresh()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    // MARK: - Loading

    private func startTimerIfNeeded() {
        guard !hasStartedTimer else { return }
        hasStartedTimer = true
        // The buffer decays in real time — re-derive twice a minute.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.trigger(.tick) }
            .store(in: &cancellables)
    }

    private func refresh() async {
        defer { state.isLoading = false }
        guard let userId else { return }

        if let account = authRepository.currentAccount {
            let first = account.displayName?.split(separator: " ").first.map(String.init)
            state.greeting = "Hi, \(first ?? "friend")"
        }

        if let profile = try? await profileRepository.fetchProfile(userId: userId) {
            coins = profile.coins
            streak = profile.streakCount
            vacationMode = profile.vacationMode
            bedtime = profile.bedtime
        }
        tasks = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        let startOfToday = Calendar.current.startOfDay(for: .now)
        completedToday = (try? await taskRepository.completedTasks(since: startOfToday, userId: userId)) ?? []
        lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        let dayAgo = Date.now.addingTimeInterval(-24 * 3600)
        completionsLast24h = (try? await taskRepository.completedTaskStats(since: dayAgo, userId: userId).count) ?? 0

        rebuildDerivedState()
    }

    // MARK: - Actions

    private func giveTreat(id: String) async {
        guard let treat = TreatCatalog.all.first(where: { $0.id == id }),
              coins >= treat.cost,
              let userId
        else { return }
        coins -= treat.cost
        bufferStore.add(lift: treat.lift, duration: treat.duration)
        Haptics.success()
        state.petSquishTrigger += 1
        rebuildDerivedState()
        await rewardsStore.spendCoins(treat.cost, userId: userId)
    }

    private func quickAdd() async {
        let title = uiState.quickAddText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let userId else { return }
        lastSubmittedQuickAddTitle = uiState.quickAddText
        state.quickAddText = ""

        // Date-only, due today — shows up in the list without stressing Mochi.
        let draft = TaskDraft(title: title, dueAt: Calendar.current.startOfDay(for: .now))
        Haptics.impact(.medium)
        let id = (try? await taskRepository.addTask(draft, userId: userId)) ?? UUID().uuidString
        tasks.append(TaskItem(
            id: id, title: title, notes: nil,
            dueAt: draft.dueAt, hasTime: false, priority: .med, listId: nil,
            repeatRule: nil, completed: false, completedAt: nil, createdAt: .now
        ))
        rebuildDerivedState()
    }

    private func toggleTask(id: String) async {
        guard let userId else { return }

        // Completing moves the task into today's done list; undoing moves
        // it back — the two arrays stay disjoint.
        let task: TaskItem
        let nowCompleted: Bool
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            task = tasks[index]
            nowCompleted = true
            var moved = tasks.remove(at: index)
            moved.completed = true
            moved.completedAt = .now
            completedToday.insert(moved, at: 0)
        } else if let index = completedToday.firstIndex(where: { $0.id == id }) {
            task = completedToday[index]
            nowCompleted = false
            var moved = completedToday.remove(at: index)
            moved.completed = false
            moved.completedAt = nil
            tasks.append(moved)
        } else {
            return
        }

        if nowCompleted {
            completionsLast24h += 1
            Haptics.success()
            state.petSquishTrigger += 1  // Mochi does a happy wiggle
        } else {
            completionsLast24h = max(0, completionsLast24h - 1)
        }

        let outcome = await completionStore.setCompleted(
            task, completed: nowCompleted, currentCoins: coins, userId: userId
        )
        coins += outcome.coinsDelta
        if let streak = outcome.streak {
            self.streak = streak
        }
        if let spawned = outcome.spawnedNext {
            tasks.append(spawned)
        }
        if let reaped = outcome.reapedTaskId {
            tasks.removeAll { $0.id == reaped }
        }
        rebuildDerivedState()
    }

    // MARK: - Derivation

    private func rebuildDerivedState() {
        let now = Date.now
        let baseline = MoodEngine.baseline(
            incompleteTasks: tasks.filter { !$0.completed },
            completionsLast24h: completionsLast24h,
            vacationMode: vacationMode,
            now: now
        )
        let buffer = bufferStore.currentValue(now: now)
        let displayed = min(100, max(0, baseline + buffer))
        let sleeping = !vacationMode && bedtime.contains(now)

        let scoped = todayScope(now: now)

        var next = uiState
        next.coins = coins
        next.streakDays = streak
        next.baseline = baseline
        next.buffer = buffer
        next.displayedMood = displayed
        next.isSleeping = sleeping
        (next.moodTitle, next.moodSub) = moodCopy(displayed, sleeping: sleeping)
        next.todayDateText = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        next.todayItems = scoped.map { item(for: $0, now: now) }
        next.doneTodayItems = completedToday.map { item(for: $0, now: now) }
        next.weekPreview = weekPreview(now: now)
        next.boostFadeText = boostFadeText(buffer: buffer, now: now)
        next.leftText = "\(scoped.count) left"
        next.showEmptyToday = scoped.isEmpty
        next.bufferLabel = "+\(Int(buffer.rounded())) / \(Int(MoodEngine.Constants.bufferCap))"
        next.petActionMeta = "+\(Int(TreatCatalog.Pet.lift)) · lasts \(TreatCatalog.Pet.durationText)"
        next.treats = TreatCatalog.all.map { treat in
            HomeBehavior.TreatUIItem(
                id: treat.id,
                name: treat.name,
                emoji: treat.emoji,
                liftText: "+\(Int(treat.lift))",
                durationText: "lasts \(treat.durationText)",
                costText: "Give · \(treat.cost) ¢",
                canAfford: coins >= treat.cost
            )
        }
        setUIState(next)
    }

    /// Overdue first (most overdue leading), then today's by time, then
    /// undated. Completed tasks live in `completedToday`, not here.
    private func todayScope(now: Date) -> [TaskItem] {
        let calendar = Calendar.current
        func bucket(_ task: TaskItem) -> Int? {
            if let hours = MoodEngine.hoursOverdue(task, now: now) {
                if hours > 0 { return 0 }
                return calendar.isDate(task.dueAt ?? now, inSameDayAs: now) ? 1 : nil
            }
            return 2 // undated — keep visible so the first task isn't orphaned
        }
        return tasks
            .compactMap { task in bucket(task).map { (task, $0) } }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                let l = lhs.0.dueAt ?? lhs.0.createdAt ?? .distantFuture
                let r = rhs.0.dueAt ?? rhs.0.createdAt ?? .distantFuture
                return l < r
            }
            .map(\.0)
    }

    /// Days 1…6 out, one compact row per day that has tasks.
    private func weekPreview(now: Date) -> [HomeBehavior.WeekPreviewItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var byOffset: [Int: [TaskItem]] = [:]
        for task in tasks {
            guard let dueAt = task.dueAt else { continue }
            let offset = calendar.dateComponents(
                [.day], from: today, to: calendar.startOfDay(for: dueAt)
            ).day ?? 0
            guard (1...6).contains(offset) else { continue }
            byOffset[offset, default: []].append(task)
        }
        return byOffset.keys.sorted().map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let dayTasks = byOffset[offset]!.sorted {
                ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
            }
            let titles = dayTasks.prefix(2).map(\.title).joined(separator: " · ")
            let extra = dayTasks.count - min(dayTasks.count, 2)
            return HomeBehavior.WeekPreviewItem(
                id: "d\(offset)",
                dayLabel: offset == 1 ? "Tomorrow" : day.formatted(.dateTime.weekday(.abbreviated)),
                summary: extra > 0 ? "\(titles) +\(extra) more" : titles,
                count: dayTasks.count
            )
        }
    }

    private func boostFadeText(buffer: Double, now: Date) -> String? {
        guard buffer > 0, let expiry = bufferStore.latestExpiry(now: now) else { return nil }
        let minutes = max(1, Int(ceil(expiry.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "boost fades in ~\(minutes)m" }
        return "boost fades in ~\(minutes / 60)h \(minutes % 60)m"
    }

    private func item(for task: TaskItem, now: Date) -> HomeBehavior.TodoUIItem {
        let display = TodoItemDisplay.row(for: task, now: now)
        let listTag = TodoItemDisplay.listTag(for: task.listId, in: lists)
        return HomeBehavior.TodoUIItem(
            id: task.id, title: task.title,
            meta: display.meta, state: display.state, chip: display.chip,
            listName: listTag?.name,
            listColor: listTag?.color
        )
    }

    private func moodCopy(_ value: Double, sleeping: Bool) -> (String, String) {
        if vacationMode {
            return ("Mochi is resting", "Vacation mode · nudges paused")
        }
        if sleeping {
            return ("Mochi is sleeping", "Bedtime · see you in the morning")
        }
        switch value {
        case 80...: return ("Mochi is beaming", "You're on a roll ✨")
        case 50..<80: return ("Mochi feels content", "Clear a task to make it beam")
        case 25..<50: return ("Mochi's getting sleepy", "A quick win would help")
        default: return ("Mochi feels low", "Let's clear something overdue")
        }
    }

}
