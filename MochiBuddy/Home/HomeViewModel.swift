//
//  HomeViewModel.swift
//  MochiBuddy
//
//  Home - the core loop on one screen: Mochi's mood tracks the task list,
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
    private let membershipSession: MembershipSession
    private let recurrenceRoller: RecurrenceRoller
    private let relay: NotificationRelaying
    private let reentryService: VacationReentryService
    private let celebrationCenter: CelebrationCenter
    private let letterService: LetterCompositionService?
    private let memoriesService: MemoriesService?

    // Domain source of truth - UIState is derived from these.
    /// Incomplete tasks only; completions move to `completedToday`.
    private var tasks: [TaskItem] = []
    private var completedToday: [TaskItem] = []
    private var lists: [TaskList] = []
    private var completionsLast24h = 0
    private var vacationMode = false
    private var vacationResumeAt: Date?
    private var vacationStartedAt: Date?
    private var lastProfile: UserProfile?
    /// The came-due-while-away pile awaiting triage, in bucket order.
    private var triageTaskIds: [String] = []
    private var bedtime: BedtimeWindow = .standard
    private var coins = 0
    private var streak = 0
    private var petName = PetNameSanitizer.defaultName
    private var hasStartedTimer = false
    /// After submit clears the field, a focused TextField can echo one last
    /// `.quickAddChanged` with the submitted title (autocorrect committing on
    /// return) and resurrect the text - swallow exactly that one echo.
    private var lastSubmittedQuickAddTitle: String?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        bufferStore: ComfortBufferStore,
        rewardsStore: RewardsStore,
        completionStore: TaskCompletionStore,
        membershipSession: MembershipSession,
        recurrenceRoller: RecurrenceRoller,
        relay: NotificationRelaying,
        reentryService: VacationReentryService,
        celebrationCenter: CelebrationCenter,
        letterService: LetterCompositionService? = nil,
        memoriesService: MemoriesService? = nil
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.bufferStore = bufferStore
        self.rewardsStore = rewardsStore
        self.completionStore = completionStore
        self.membershipSession = membershipSession
        self.recurrenceRoller = recurrenceRoller
        self.relay = relay
        self.reentryService = reentryService
        self.celebrationCenter = celebrationCenter
        self.letterService = letterService
        self.memoriesService = memoriesService
        super.init(initialState: HomeBehavior.UIState())
    }

    /// The envelope impression logs once per session, not per rebuild.
    private var letterImpressionLogged = false

    override func triggerAsync(_ action: HomeBehavior.ViewAction) async {
        switch action {
        case .refresh:
            startTimerIfNeeded()
            await refresh()

        case .tick:
            rebuildDerivedState()

        case .petTapped:
            // Lapsed: tap-to-pet is off - Mochi's napping until they're back.
            guard !uiState.isLapsed else { return }
            bufferStore.add(lift: TreatCatalog.Pet.lift, duration: TreatCatalog.Pet.duration)
            Haptics.impact(.soft)
            state.petSquishTrigger += 1
            rebuildDerivedState()
            // The buffer lifts the forecast - scheduled pings must follow.
            relay.requestRelay(.comfortChange)

        case .treatsTapped:
            guard !uiState.isLapsed else { return }
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
            guard !uiState.isLapsed else { return }
            await quickAdd()

        case .composeTapped:
            guard !uiState.isLapsed else { return }
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
            relay.requestRelay(.taskChange)

        case .letterEnvelopeTapped:
            if let unread = letterService?.unreadLetter {
                state.presentedLetter = HomeBehavior.PresentedLetter(letter: unread, source: .home)
            }

        case .letterDismissed:
            state.presentedLetter = nil
            rebuildDerivedState()

        case .dismissCelebration:
            state.celebrationText = nil

        case .endVacationTapped, .vacationWelcomeBack:
            guard let userId = authRepository.currentAccount?.uid else { return }
            Haptics.impact(.light)
            state.showVacationCheckIn = false
            await reentryService.endNow(userId: userId)
            await refresh()

        case .vacationKeepResting:
            reentryService.snoozeCheckIn()
            state.showVacationCheckIn = false

        case .triageComplete(let id):
            await triageComplete([id])
        case .triageCompleteAll:
            await triageComplete(triageTaskIds)
        case .triageReschedule(let id):
            await triageReschedule([id])
        case .triageRescheduleAll:
            await triageReschedule(triageTaskIds)
        case .triageDismiss(let id):
            await triageDismiss([id])
        case .triageDismissAll:
            await triageDismiss(triageTaskIds)
        case .triageLater:
            // Skipping is fine - the grace buffer is already holding Mochi
            // at content while the pile reasserts honestly over 24h.
            reentryService.clearPendingTriage()
            triageTaskIds = []
            state.showTriage = false
            rebuildDerivedState()
        }
    }

    // MARK: - Re-entry triage

    private func triageComplete(_ ids: [String]) async {
        guard let userId else { return }
        for id in ids {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { continue }
            var moved = tasks.remove(at: index)
            moved.completed = true
            moved.completedAt = .now
            completedToday.insert(moved, at: 0)
            completionsLast24h += 1
            let outcome = await completionStore.setCompleted(
                moved, completed: true, currentCoins: coins, userId: userId
            )
            coins += outcome.coinsDelta
            if let newStreak = outcome.streak {
                streak = newStreak
            }
        }
        Haptics.success()
        state.petSquishTrigger += 1
        finishTriage(resolved: ids)
    }

    private func triageReschedule(_ ids: [String]) async {
        guard let userId else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for (offset, id) in ids.enumerated() {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { continue }
            // Spread across the coming days - triage must defuse the pile,
            // not rebuild it on tomorrow's doorstep.
            let day = calendar.date(byAdding: .day, value: 1 + (offset % 5), to: today) ?? today
            tasks[index].dueAt = day
            tasks[index].hasTime = false
            try? await taskRepository.updateTask(tasks[index], userId: userId)
        }
        Haptics.success()
        finishTriage(resolved: ids)
        relay.requestRelay(.taskChange)
    }

    private func triageDismiss(_ ids: [String]) async {
        guard let userId else { return }
        for id in ids {
            tasks.removeAll { $0.id == id }
            try? await taskRepository.deleteTask(id: id, userId: userId)
        }
        finishTriage(resolved: ids)
        relay.requestRelay(.taskChange)
    }

    private func finishTriage(resolved: [String]) {
        triageTaskIds.removeAll { resolved.contains($0) }
        if triageTaskIds.isEmpty {
            reentryService.clearPendingTriage()
            state.showTriage = false
        }
        rebuildDerivedState()
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    // MARK: - Loading

    private func startTimerIfNeeded() {
        guard !hasStartedTimer else { return }
        hasStartedTimer = true
        // The buffer decays in real time - re-derive twice a minute.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.trigger(.tick) }
            .store(in: &cancellables)
    }

    private func refresh() async {
        defer { state.isLoading = false }
        guard let userId else { return }

        var profile = try? await profileRepository.fetchProfile(userId: userId)
        // Prefer the profile's name: Apple only hands the auth account a
        // name on the very first authorization, so the profile document is
        // the durable source (and the one the user can edit on the You tab).
        let name = profile?.displayName ?? authRepository.currentAccount?.displayName
        let first = name?.split(separator: " ").first.map(String.init)
        state.greeting = "Hi, \(first ?? "friend")"
        // A vacation that ended while away (date passed / cap hit) gets
        // its re-entry here, on the first open - then reload the profile
        // the service just cleared.
        if let current = profile,
           await reentryService.processIfEnded(profile: current, userId: userId) {
            profile = try? await profileRepository.fetchProfile(userId: userId)
        }
        if let profile {
            coins = profile.coins
            streak = profile.streakCount
            petName = profile.mochiName
            vacationMode = profile.vacationMode
            vacationResumeAt = profile.vacationResumeAt
            vacationStartedAt = profile.vacationStartedAt
            bedtime = profile.bedtime
        }
        lastProfile = profile
        tasks = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        // One-live-occurrence invariant: re-stamp recurring tasks whose next
        // occurrence has come due. Frozen while on vacation (recurrence
        // pauses) or lapsed (the list drains, nothing self-replenishes).
        tasks = await recurrenceRoller.rollForward(
            tasks,
            frozen: vacationActive(now: .now) || membershipSession.isLapsed,
            userId: userId
        )
        let startOfToday = Calendar.current.startOfDay(for: .now)
        completedToday = (try? await taskRepository.completedTasks(since: startOfToday, userId: userId)) ?? []
        lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        let dayAgo = Date.now.addingTimeInterval(-24 * 3600)
        completionsLast24h = (try? await taskRepository.completedTaskStats(since: dayAgo, userId: userId).count) ?? 0

        // A pending triage pile (left by re-entry, wherever it happened)
        // surfaces here; ids whose tasks are gone silently drop out.
        let pendingIds = reentryService.pendingTriageIds()
        triageTaskIds = pendingIds.filter { id in tasks.contains { $0.id == id } }
        if !pendingIds.isEmpty, triageTaskIds.isEmpty {
            reentryService.clearPendingTriage()
        }
        if !triageTaskIds.isEmpty {
            state.showTriage = true
        }

        // A tapped letter invitation routes straight to its letter.
        if let letterService, let pendingId = letterService.pendingNotificationOpen {
            letterService.pendingNotificationOpen = nil
            if let letter = await letterService.letter(id: pendingId) {
                state.presentedLetter = HomeBehavior.PresentedLetter(
                    letter: letter, source: .notification
                )
            }
        }

        // Today's anniversary banner, if any, lands in the celebration
        // center on the day's first open (once per milestone; a streak
        // milestone owns a collided date; silent on vacation and lapse).
        await memoriesService?.checkAnniversaryBanner(now: .now)

        rebuildDerivedState()
    }

    // MARK: - Actions

    private func giveTreat(id: String) async {
        guard !uiState.isLapsed else { return }
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
        relay.requestRelay(.comfortChange)
    }

    private func quickAdd() async {
        let title = uiState.quickAddText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let userId else { return }
        lastSubmittedQuickAddTitle = uiState.quickAddText
        state.quickAddText = ""

        // Date-only, due today - shows up in the list without stressing Mochi.
        let draft = TaskDraft(title: title, dueAt: Calendar.current.startOfDay(for: .now))
        Haptics.impact(.medium)
        let id = (try? await taskRepository.addTask(draft, userId: userId)) ?? UUID().uuidString
        tasks.append(TaskItem(
            id: id, title: title, notes: nil,
            dueAt: draft.dueAt, hasTime: false, priority: .med, listId: nil,
            repeatRule: nil, completed: false, completedAt: nil, createdAt: .now
        ))
        rebuildDerivedState()
        relay.requestRelay(.taskChange)
    }

    private func toggleTask(id: String) async {
        guard let userId else { return }

        // Completing moves the task into today's done list; undoing moves
        // it back - the two arrays stay disjoint.
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
        let onVacation = vacationActive(now: now)
        let baseline = MoodEngine.baseline(
            incompleteTasks: tasks.filter { !$0.completed },
            completionsLast24h: completionsLast24h,
            vacationMode: onVacation,
            now: now
        )
        let buffer = bufferStore.currentValue(now: now)
        let displayed = min(100, max(0, baseline + buffer))
        // Lapsed wins over vacation and bedtime: Mochi is asleep, dormant
        // and peaceful - never sad as conversion pressure. Vacation pins
        // the resting pose so buffer decay can't make Mochi look anxious
        // mid-trip.
        let lapsed = membershipSession.isLapsed
        let sleeping = lapsed || onVacation || bedtime.contains(now)

        let scoped = todayScope(now: now)

        var next = uiState
        // A milestone landed anywhere (this screen, Tasks, a notification
        // action, the widget drain) celebrates here, on Mochi's surface.
        if let milestone = celebrationCenter.consumeMilestone() {
            next.celebrationText = StreakMilestones.celebrationText(days: milestone, petName: petName)
        } else if let anniversary = celebrationCenter.consumeAnniversary() {
            // The general collision rule already kept this slot empty on
            // any streak-claimed date, so first-come rendering is safe.
            next.celebrationText = anniversary
        }
        next.mochiName = petName
        next.subGreeting = "Let's keep \(petName) happy"
        // In-app CTA fallback: verb-only when the name is too wide for the
        // button; VoiceOver keeps the full name at the call sites.
        let nameFits = NotificationActionTitles.fitsCompactBudget(petName)
        next.wakeCtaTitle = nameFits ? "Wake \(petName)" : "Wake"
        next.petCtaTitle = nameFits ? "Pet \(petName)" : "Pet"
        next.isLapsed = lapsed
        // The quiet envelope: an unread letter waits near Mochi. Never
        // shown lapsed (letters pause; the archive stays reachable in You).
        let unreadLetter = lapsed ? nil : letterService?.unreadLetter
        next.showLetterEnvelope = unreadLetter != nil
        next.letterEnvelopeText = "A letter from \(petName)"
        if unreadLetter != nil, !letterImpressionLogged {
            letterImpressionLogged = true
            letterService?.logIndicatorShown()
        }
        next.showBillingBanner = membershipSession.hasBillingIssue
        next.isOnVacation = onVacation && !lapsed
        next.vacationBanner = next.isOnVacation ? vacationBannerText() : nil
        next.showVacationCheckIn = next.isOnVacation
            && (lastProfile.map { reentryService.checkInDue(profile: $0, now: now) } ?? false)
        next.triageItems = triageTaskIds.compactMap { id in
            tasks.first { $0.id == id }.map { task in
                HomeBehavior.TriageItem(
                    id: task.id,
                    title: task.title,
                    meta: TodoItemDisplay.row(for: task, now: now).meta
                )
            }
        }
        next.coins = coins
        next.streakDays = streak
        next.baseline = baseline
        next.buffer = buffer
        next.displayedMood = displayed
        next.isSleeping = sleeping
        (next.moodTitle, next.moodSub) = moodCopy(
            displayed, sleeping: sleeping, lapsed: lapsed, vacation: onVacation, petName: petName
        )
        next.todayDateText = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        next.todayItems = scoped.map { item(for: $0, now: now) }
        next.doneTodayItems = completedToday.map { item(for: $0, now: now) }
        next.weekPreview = weekPreview(now: now)
        next.boostFadeText = lapsed ? nil : boostFadeText(buffer: buffer, now: now)
        next.leftText = "\(scoped.count) left"
        next.showEmptyToday = scoped.isEmpty
        next.bufferLabel = "+\(Int(buffer.rounded())) / \(Int(MoodEngine.Constants.bufferCap))"
        next.petActionMeta = "+\(Int(TreatCatalog.Pet.lift)) · lasts \(TreatCatalog.Pet.durationText)"
        next.treats = TreatCatalog.all.map { treat in
            HomeBehavior.TreatUIItem(
                id: treat.id,
                name: treat.name,
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
            return 2 // undated - keep visible so the first task isn't orphaned
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
            listColor: listTag?.color,
            isRecurring: task.repeatRule != nil
        )
    }

    /// Vacation with auto-expiry applied - the same rule the forecast uses.
    private func vacationActive(now: Date) -> Bool {
        VacationSchedule.isActive(
            mode: vacationMode, startedAt: vacationStartedAt,
            resumeAt: vacationResumeAt, at: now
        )
    }

    private func vacationBannerText() -> String {
        guard vacationResumeAt != nil,
              let end = VacationSchedule.effectiveEnd(
                  startedAt: vacationStartedAt, resumeAt: vacationResumeAt
              )
        else {
            return "On vacation · back whenever you're ready"
        }
        return "On vacation · back \(end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private func moodCopy(_ value: Double, sleeping: Bool, lapsed: Bool, vacation: Bool, petName: String) -> (String, String) {
        if lapsed {
            return ("\(petName) is napping", "Wake \(petName) to bring everything back")
        }
        if vacation {
            return ("\(petName) is resting", "Vacation mode · nudges paused")
        }
        if sleeping {
            return ("\(petName) is sleeping", "Bedtime · see you in the morning")
        }
        switch value {
        case 80...: return ("\(petName) is beaming", "You're on a roll")
        case 50..<80: return ("\(petName) feels content", "Clear a task to make it beam")
        case 25..<50: return ("\(petName) is getting sleepy", "A quick win would help")
        default: return ("\(petName) feels low", "Let's clear something overdue")
        }
    }

}
