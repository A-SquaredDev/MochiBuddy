//
//  HomeViewModel.swift
//  MochiBuddy
//
//  Home — the core loop on one screen: Mochi's mood tracks the task list,
//  completing tasks earns coins, pets/treats buy temporary comfort. The
//  baseline comes from MoodEngine; the buffer decays via a 30s tick.
//

import UIKit
import Combine

final class HomeViewModel: StateViewModel<
    HomeBehavior.UIState,
    HomeBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let bufferStore: ComfortBufferStore
    private let rewardsStore: RewardsStore
    private let completionStore: TaskCompletionStore

    // Domain source of truth — UIState is derived from these.
    private var tasks: [TaskItem] = []
    private var completionsLast24h = 0
    private var vacationMode = false
    private var coins = 0
    private var streak = 0
    private var hasStartedTimer = false

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        bufferStore: ComfortBufferStore,
        rewardsStore: RewardsStore,
        completionStore: TaskCompletionStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
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
            state.quickAddText = text

        case .quickAddSubmitted:
            await quickAdd()

        case .toggleTask(let id):
            await toggleTask(id: id)

        case .taskTapped(let id):
            if let task = tasks.first(where: { $0.id == id }) {
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
        guard let userId else { return }

        if let account = authRepository.currentAccount {
            let first = account.displayName?.split(separator: " ").first.map(String.init)
            state.greeting = "Hi, \(first ?? "friend")"
        }

        if let profile = try? await profileRepository.fetchProfile(userId: userId) {
            coins = profile.coins
            streak = profile.streakCount
            vacationMode = profile.vacationMode
        }
        tasks = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
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
        guard let index = tasks.firstIndex(where: { $0.id == id }), let userId else { return }
        let nowCompleted = !tasks[index].completed
        let task = tasks[index]
        tasks[index].completed = nowCompleted
        tasks[index].completedAt = nowCompleted ? .now : nil

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

        let scoped = todayScope(now: now)
        let remaining = scoped.filter { !$0.completed }.count

        var next = uiState
        next.coins = coins
        next.streakDays = streak
        next.baseline = baseline
        next.buffer = buffer
        next.displayedMood = displayed
        (next.moodTitle, next.moodSub) = moodCopy(displayed)
        next.todayItems = scoped.prefix(4).map { item(for: $0, now: now) }
        next.leftText = "\(remaining) left"
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
    /// undated. Tasks completed this session stay visible as done rows.
    private func todayScope(now: Date) -> [TaskItem] {
        let calendar = Calendar.current
        func bucket(_ task: TaskItem) -> Int? {
            if task.completed { return 1 }
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

    private func item(for task: TaskItem, now: Date) -> HomeBehavior.TodoUIItem {
        let state: TodoRowState
        let meta: String

        if task.completed {
            state = .done
            meta = "Done · nice one"
        } else if let hours = MoodEngine.hoursOverdue(task, now: now), hours > 0 {
            state = .overdue
            meta = "⏰ Overdue by \(Self.overdueText(hours: hours))"
        } else if let dueAt = task.dueAt {
            let timeText = dueAt.formatted(date: .omitted, time: .shortened)
            if task.hasTime, dueAt.timeIntervalSince(now) < 3 * 3600 {
                state = .due
                meta = "Due soon · \(timeText)"
            } else {
                state = .normal
                meta = task.hasTime ? "Due today · \(timeText)" : "Due later today"
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

        return HomeBehavior.TodoUIItem(id: task.id, title: task.title, meta: meta, state: state, chip: chip)
    }

    private func moodCopy(_ value: Double) -> (String, String) {
        if vacationMode {
            return ("Mochi is resting", "Vacation mode · nudges paused")
        }
        switch value {
        case 80...: return ("Mochi is beaming", "You're on a roll ✨")
        case 50..<80: return ("Mochi feels content", "Clear a task to make it beam")
        case 25..<50: return ("Mochi's getting sleepy", "A quick win would help")
        default: return ("Mochi feels low", "Let's clear something overdue")
        }
    }

    private static func overdueText(hours: Double) -> String {
        if hours < 1 { return "a moment" }
        if hours < 24 {
            let h = Int(hours)
            return "\(h) hr"
        }
        let days = Int(hours / 24)
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}
