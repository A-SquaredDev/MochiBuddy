//
//  TaskEditorViewModel.swift
//  MochiBuddy
//
//  Add & Edit task - the full field set (title, when, priority, list,
//  repeat, notes) plus snooze and delete in edit mode. The domain task
//  is the source of truth; every action mutates it then re-derives.
//

import SwiftUI

final class TaskEditorViewModel: ObservableStateViewModel<
    TaskEditorBehavior.UIState,
    TaskEditorBehavior.ViewAction,
    TaskEditorBehavior.NavigationEvent
> {

    private static let inboxId = "inbox"
    private static let noRepeatId = "none"
    private static let customRepeatId = "custom"
    private static let lowPriorityDot = Color(hex: 0x8FD3F4)

    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let suggestionService: SuggestionService?
    private let editingTask: TaskItem?

    // Domain source of truth.
    private var draft: TaskDraft
    private var lists: [TaskList] = []

    // Suggested times (Personal Layer, Feature 5). One editor open = one
    // session: a trigger presents at most once, and a presented proposal
    // is FROZEN - it never regenerates as fields toggle. Lifecycle and
    // outcome classification live here; all math is the pure engine's.
    private enum SuggestionLifecycle { case offered, confirmed, dismissed }
    private var suggestionSession: SuggestionService.Session?
    private var presentedProposals: [SuggestionTrigger: SuggestionProposal] = [:]
    private var suggestionLifecycles: [SuggestionTrigger: SuggestionLifecycle] = [:]
    private var tappedTriggers: Set<SuggestionTrigger> = []
    private var evaluatedTriggers: Set<SuggestionTrigger> = []
    private var suggestionContextCache: (key: String, context: SuggestionEngine.Context)?

    init(
        editingTask: TaskItem?,
        draftTitle: String? = nil,
        draftListId: String? = nil,
        petName: String = "Mochi",
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        suggestionService: SuggestionService? = nil
    ) {
        self.editingTask = editingTask
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.suggestionService = suggestionService
        if let task = editingTask {
            draft = TaskDraft(
                title: task.title,
                notes: task.notes,
                dueAt: task.dueAt,
                hasTime: task.hasTime,
                priority: task.priority,
                listId: task.listId,
                repeatRule: task.repeatRule
            )
        } else {
            // Fast capture defaults to due today (date-only). Callers may
            // seed a title (Home quick-add → plus) or a list (list detail).
            draft = TaskDraft(
                title: draftTitle ?? "",
                dueAt: Calendar.current.startOfDay(for: .now),
                listId: draftListId
            )
        }
        // Seed the fields the View reads before `.load` finishes - the
        // onLoad focus check consults `isEditing` synchronously.
        var initial = TaskEditorBehavior.UIState()
        initial.petName = petName
        initial.isEditing = editingTask != nil
        initial.title = draft.title
        initial.canSave = !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: TaskEditorBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId {
                lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
            }
            suggestionSession = await suggestionService?.beginSession(editingTask: editingTask)
            rebuild(picker: .none)

        case .titleChanged(let title):
            draft.title = title
            state.title = title
            state.canSave = !title.trimmingCharacters(in: .whitespaces).isEmpty

        case .selectDateOption(let id):
            selectDateOption(id)

        case .timeTapped:
            if !draft.hasTime {
                // Adding a time defaults to the next round hour today.
                let base = draft.dueAt ?? .now
                draft.dueAt = Self.combine(day: base, time: Self.nextRoundHour())
                draft.hasTime = true
            }
            rebuild(picker: uiState.activePicker == .time ? .none : .time)

        case .clearTimeTapped:
            if let dueAt = draft.dueAt {
                draft.dueAt = Calendar.current.startOfDay(for: dueAt)
            }
            draft.hasTime = false
            rebuild(picker: .none)

        case .dateChanged(let date):
            // Only honor the calendar while it's shown - a picker being
            // dismissed can echo a value change and resurrect a cleared date.
            guard uiState.activePicker == .date else { return }
            let time = draft.hasTime ? (draft.dueAt ?? date) : nil
            draft.dueAt = time.map { Self.combine(day: date, time: $0) }
                ?? Calendar.current.startOfDay(for: date)
            rebuild(picker: uiState.activePicker)

        case .timeChanged(let time):
            guard uiState.activePicker == .time else { return }
            draft.dueAt = Self.combine(day: draft.dueAt ?? .now, time: time)
            draft.hasTime = true
            rebuild(picker: uiState.activePicker)

        case .suggestionTapped:
            acceptSuggestion()

        case .suggestionDismissed:
            dismissSuggestion()

        case .selectPriority(let id):
            draft.priority = TaskPriority(rawValue: id) ?? .med
            rebuild(picker: uiState.activePicker)

        case .selectList(let id):
            draft.listId = id == Self.inboxId ? nil : id
            rebuild(picker: uiState.activePicker)

        case .selectRepeat(let id):
            selectRepeat(id)

        case .toggleRepeatDay(let day):
            toggleRepeatDay(day)

        case .notesChanged(let notes):
            draft.notes = notes.isEmpty ? nil : notes
            state.notes = notes

        case .saveTapped:
            await save()

        case .snoozeTapped:
            await snooze()

        case .deleteTapped:
            guard let task = editingTask, let userId else { return }
            // A recurring task gets a choice: skip just this occurrence, or
            // end the series. (Skipping needs a date to roll forward from.)
            if task.repeatRule != nil, task.dueAt != nil {
                state.showDeleteOptions = true
                return
            }
            state.isWorking = true
            try? await taskRepository.deleteTask(id: task.id, userId: userId)
            setNavigationEvent(.done)

        case .confirmSkipOccurrence:
            guard let task = editingTask, let rule = task.repeatRule,
                  let due = task.dueAt, let userId else { return }
            state.showDeleteOptions = false
            state.isWorking = true
            var skipped = task
            skipped.dueAt = rule.nextOccurrence(after: due)
            try? await taskRepository.updateTask(skipped, userId: userId)
            setNavigationEvent(.done)

        case .confirmDeleteSeries:
            guard let task = editingTask, let userId else { return }
            state.showDeleteOptions = false
            state.isWorking = true
            try? await taskRepository.deleteTask(id: task.id, userId: userId)
            setNavigationEvent(.done)

        case .cancelDeleteOptions:
            state.showDeleteOptions = false

        case .confirmSaveOccurrence:
            await saveDetachedOccurrence()

        case .confirmSaveSeries:
            state.showSaveScopeOptions = false
            await performSave()

        case .cancelSaveScope:
            state.showSaveScopeOptions = false
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    // MARK: - When

    private func selectDateOption(_ id: String) {
        let calendar = Calendar.current
        switch TaskEditorBehavior.DateOption(rawValue: id) {
        case .noDate:
            draft.dueAt = nil
            draft.hasTime = false
            rebuild(picker: .none)

        case .today:
            moveToDay(calendar.startOfDay(for: .now))
            rebuild(picker: .none)

        case .tomorrow:
            let today = calendar.startOfDay(for: .now)
            moveToDay(calendar.date(byAdding: .day, value: 1, to: today) ?? today)
            rebuild(picker: .none)

        case .pick:
            if draft.dueAt == nil {
                draft.dueAt = calendar.startOfDay(for: .now)
            }
            rebuild(picker: uiState.activePicker == .date ? .none : .date)

        case nil:
            break
        }
    }

    /// Changes the day while keeping any chosen time of day.
    private func moveToDay(_ day: Date) {
        if draft.hasTime, let current = draft.dueAt {
            draft.dueAt = Self.combine(day: day, time: current)
        } else {
            draft.dueAt = day
        }
    }

    // MARK: - Repeat

    private func selectRepeat(_ id: String) {
        if id == Self.customRepeatId {
            // Keep an existing day selection; otherwise seed with the due
            // date's weekday so the rule starts out matching the task.
            if draft.repeatRule?.customDays == nil {
                let anchor = draft.dueAt ?? .now
                draft.repeatRule = .custom([Calendar.current.component(.weekday, from: anchor)])
            }
        } else {
            draft.repeatRule = TaskRepeat(freq: id)
        }
        rebuild(picker: uiState.activePicker)
    }

    private func toggleRepeatDay(_ day: Int) {
        guard case .custom(var days) = draft.repeatRule else { return }
        if days.contains(day) {
            // A custom rule needs at least one day - ignore removing the last.
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            days.insert(day)
        }
        draft.repeatRule = .custom(days)
        rebuild(picker: uiState.activePicker)
    }

    // MARK: - Side effects

    private func save() async {
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        draft.title = title

        // Editing a recurring task with its rule intact: ask whether the
        // change is for this occurrence or the series. A rule change is a
        // series-level edit by definition, so it saves straight through.
        // (Detaching needs the original date to roll the series forward.)
        if let task = editingTask, task.dueAt != nil,
           task.repeatRule != nil, draft.repeatRule == task.repeatRule {
            state.showSaveScopeOptions = true
            return
        }
        await performSave()
    }

    private func performSave() async {
        guard let userId else { return }
        state.isWorking = true
        classifySuggestionOutcomes()

        if let task = editingTask {
            var updated = task
            updated.title = draft.title
            updated.notes = draft.notes
            updated.dueAt = draft.dueAt
            updated.hasTime = draft.hasTime
            updated.priority = draft.priority
            updated.listId = draft.listId
            updated.repeatRule = draft.repeatRule
            try? await taskRepository.updateTask(
                updated,
                countingReschedule: Self.pushesDueDateLater(task, to: draft.dueAt),
                userId: userId
            )
        } else {
            // The preallocated id (when a suggestion session minted one)
            // keeps a pre-save chip dismissal attached to this task.
            _ = try? await taskRepository.addTask(
                draft, id: suggestionSession?.preallocatedTaskId, userId: userId
            )
        }
        Haptics.success()
        setNavigationEvent(.done)
    }

    /// "This occurrence only": the edited task detaches into a one-off, and
    /// a fresh document due at the next occurrence carries the series on
    /// with the original details.
    private func saveDetachedOccurrence() async {
        guard let task = editingTask, let rule = task.repeatRule,
              let due = task.dueAt, let userId else { return }
        state.showSaveScopeOptions = false
        state.isWorking = true

        classifySuggestionOutcomes()
        var detached = task
        detached.title = draft.title
        detached.notes = draft.notes
        detached.dueAt = draft.dueAt
        detached.hasTime = draft.hasTime
        detached.priority = draft.priority
        detached.listId = draft.listId
        detached.repeatRule = nil
        try? await taskRepository.updateTask(
            detached,
            countingReschedule: Self.pushesDueDateLater(task, to: draft.dueAt),
            userId: userId
        )

        let continuation = TaskDraft(
            title: task.title,
            notes: task.notes,
            dueAt: rule.nextOccurrence(after: due),
            hasTime: task.hasTime,
            priority: task.priority,
            listId: task.listId,
            repeatRule: rule
        )
        _ = try? await taskRepository.addTask(continuation, userId: userId)
        Haptics.success()
        setNavigationEvent(.done)
    }

    /// A user move of an incomplete task's due date to a LATER calendar day
    /// is a push and counts toward rescheduleCount, same as snooze. Adding
    /// a date, clearing one, moving earlier, or re-timing within the same
    /// day is not a push. Skip-occurrence and vacation triage never route
    /// through here - different intents, never counted.
    static func pushesDueDateLater(
        _ task: TaskItem, to newDueAt: Date?, calendar: Calendar = .current
    ) -> Bool {
        guard !task.completed, let oldDue = task.dueAt, let newDue = newDueAt else {
            return false
        }
        return calendar.startOfDay(for: newDue) > calendar.startOfDay(for: oldDue)
    }

    /// Pushes the due date a day forward (design doc: snooze increments the
    /// reschedule counter - the v2 procrastination signal).
    private func snooze() async {
        guard let task = editingTask, let userId else { return }
        let calendar = Calendar.current
        let base = max(task.dueAt ?? .now, calendar.startOfDay(for: .now))
        let newDue = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        state.isWorking = true
        try? await taskRepository.snoozeTask(id: task.id, to: newDue, userId: userId)
        setNavigationEvent(.done)
    }

    // MARK: - Suggested times (Personal Layer, Feature 5)

    /// The task's series identity - a recurring habit is one identity
    /// (`seriesId ?? id`). Only an EXISTING task has one: a brand-new
    /// series has no completions to learn from. Never inferred from
    /// titles - titles are user content, not identity.
    private var seriesIdentity: String? {
        guard let task = editingTask, task.repeatRule != nil || task.seriesId != nil else {
            return nil
        }
        return task.seriesId ?? task.id
    }

    private var currentTaskId: String? {
        editingTask?.id ?? suggestionSession?.preallocatedTaskId
    }

    /// Evaluate any trigger that has not presented yet. Presented
    /// proposals are frozen; a trigger that evaluated blocked keeps
    /// re-evaluating as fields change (the chip may still appear), but
    /// its denominator event fires only once per session.
    private func refreshSuggestions(now: Date = .now) {
        guard let service = suggestionService, let session = suggestionSession else { return }

        let key = "\(seriesIdentity ?? "-")|\(draft.listId ?? "-")"
        let context: SuggestionEngine.Context
        if let cached = suggestionContextCache, cached.key == key {
            context = cached.context
        } else {
            context = service.engineContext(
                session: session, seriesIdentity: seriesIdentity, listId: draft.listId, now: now
            )
            suggestionContextCache = (key, context)
        }

        let calendar = Calendar.current
        let snapshot = SuggestionEngine.TaskSnapshot(
            listId: draft.listId,
            isRecurring: draft.repeatRule != nil,
            hasTime: draft.hasTime,
            scheduledMinute: draft.hasTime ? draft.dueAt.map { Self.minuteOfDay($0, calendar: calendar) } : nil,
            dueDay: draft.dueAt.map { CivilDay(of: $0, in: calendar).dateString },
            // Structural: Apple Reminders rows never open this editor.
            isAppleSource: false
        )

        for trigger in SuggestionTrigger.allCases where suggestionLifecycles[trigger] == nil {
            let dismissKeyId = trigger == .newTime ? currentTaskId : seriesIdentity
            guard let dismissKeyId else { continue }
            let dismissedAt = service.dismissedMinute(trigger, id: dismissKeyId, userId: session.userId)
            let evaluation = trigger == .newTime
                ? SuggestionEngine.evaluateNewTime(task: snapshot, context: context, dismissedAt: dismissedAt)
                : SuggestionEngine.evaluateReTime(task: snapshot, context: context, dismissedAt: dismissedAt)
            // An empty evaluation means the trigger's preconditions never
            // held - nothing happened, nothing to report.
            guard evaluation.proposal != nil || evaluation.blocked != nil else { continue }
            if !evaluatedTriggers.contains(trigger) {
                evaluatedTriggers.insert(trigger)
                service.recordEvaluated(evaluation, userId: session.userId)
            }
            if let proposal = evaluation.proposal {
                presentedProposals[trigger] = proposal
                suggestionLifecycles[trigger] = .offered
                service.recordShown(proposal, userId: session.userId)
            }
        }
    }

    /// The chip the View renders right now, derived from the frozen
    /// proposals: manual changes can satisfy or remove a chip, but never
    /// regenerate one.
    private func suggestionChipState() -> TaskEditorBehavior.SuggestionChip? {
        for trigger in [SuggestionTrigger.reTime, .newTime] {
            guard let proposal = presentedProposals[trigger],
                  let lifecycle = suggestionLifecycles[trigger]
            else { continue }
            let listName = proposal.listId.flatMap { id in lists.first { $0.id == id }?.name }
            switch lifecycle {
            case .dismissed:
                continue
            case .confirmed:
                // Quiet confirmed state; everything stays editable. A
                // cleared time retires the row (the outcome classifier
                // still remembers the tap).
                guard draft.hasTime else { continue }
                return TaskEditorBehavior.SuggestionChip(
                    label: SuggestionCopy.confirmed(minute: proposal.displayedMinute),
                    reason: "",
                    accessibilityLabel: SuggestionCopy.confirmed(minute: proposal.displayedMinute),
                    isConfirmed: true
                )
            case .offered:
                guard offeredPreconditionsHold(trigger, proposal: proposal) else { continue }
                return TaskEditorBehavior.SuggestionChip(
                    label: SuggestionCopy.chipLabel(proposal, petName: uiState.petName),
                    reason: SuggestionCopy.reason(proposal, listName: listName),
                    accessibilityLabel: SuggestionCopy.accessibilityLabel(
                        proposal, petName: uiState.petName, listName: listName
                    ),
                    isConfirmed: false
                )
            }
        }
        return nil
    }

    private func offeredPreconditionsHold(
        _ trigger: SuggestionTrigger, proposal: SuggestionProposal
    ) -> Bool {
        switch trigger {
        case .newTime:
            // A manually chosen time satisfies or replaces the offer.
            return draft.dueAt != nil && !draft.hasTime
        case .reTime:
            guard draft.repeatRule != nil, draft.hasTime, let dueAt = draft.dueAt else {
                return false
            }
            // A manual pick near the proposal is a match - the chip's
            // job is done (the classifier records it at save).
            let minute = Self.minuteOfDay(dueAt)
            return SuggestionEngine.circularDistance(minute, proposal.displayedMinute) > 30
        }
    }

    private var visibleOfferedTrigger: SuggestionTrigger? {
        for trigger in [SuggestionTrigger.reTime, .newTime] {
            guard let proposal = presentedProposals[trigger],
                  suggestionLifecycles[trigger] == .offered,
                  offeredPreconditionsHold(trigger, proposal: proposal)
            else { continue }
            return trigger
        }
        return nil
    }

    /// Sets the time exactly as a manual pick would - fully editable
    /// after; saving proceeds through the normal editor path.
    private func acceptSuggestion() {
        guard let trigger = visibleOfferedTrigger,
              let proposal = presentedProposals[trigger]
        else { return }
        tappedTriggers.insert(trigger)
        suggestionLifecycles[trigger] = .confirmed
        let base = draft.dueAt ?? Calendar.current.startOfDay(for: .now)
        draft.dueAt = Self.combine(day: base, minuteOfDay: proposal.displayedMinute)
        draft.hasTime = true
        Haptics.success()
        rebuild(picker: .none)
    }

    /// No confirmation, no "are you sure" - the ledger remembers the
    /// displayed minute so the same proposal stays gone until it moves.
    private func dismissSuggestion() {
        guard let service = suggestionService, let session = suggestionSession,
              let trigger = visibleOfferedTrigger,
              let proposal = presentedProposals[trigger],
              let id = trigger == .newTime ? currentTaskId : seriesIdentity
        else { return }
        suggestionLifecycles[trigger] = .dismissed
        service.recordDismissed(
            trigger, id: id, displayedMinute: proposal.displayedMinute, userId: session.userId
        )
        Haptics.impact(.light)
        rebuild(picker: uiState.activePicker)
    }

    /// Save-based terminal outcomes, classified once. Precedence: tapped
    /// state > matched state > dismissed > ignored - a dismiss followed
    /// by manually choosing the suggested time is MATCHED, the more
    /// informative signal. Cancel never reaches here: an abandoned
    /// session is not evidence against the suggestion.
    private func classifySuggestionOutcomes() {
        guard let service = suggestionService, let session = suggestionSession,
              let taskId = currentTaskId
        else { return }
        let savedMinute = draft.hasTime ? draft.dueAt.map { Self.minuteOfDay($0) } : nil
        for (trigger, proposal) in presentedProposals {
            let outcome: SuggestionOutcome
            if tappedTriggers.contains(trigger) {
                outcome = savedMinute == proposal.displayedMinute ? .accepted : .adjusted
            } else if let savedMinute,
                      SuggestionEngine.circularDistance(savedMinute, proposal.displayedMinute) <= 30 {
                outcome = .matched
            } else if suggestionLifecycles[trigger] == .dismissed {
                outcome = .dismissed
            } else {
                outcome = .ignored
            }
            service.recordOutcome(
                outcome, proposal: proposal, taskId: taskId,
                seriesId: seriesIdentity, userId: session.userId
            )
        }
        presentedProposals = [:]
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func combine(day: Date, minuteOfDay minute: Int, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day
        ) ?? day
    }

    // MARK: - Derivation

    private func rebuild(picker: TaskEditorBehavior.PickerTarget) {
        refreshSuggestions()
        let calendar = Calendar.current
        var next = uiState
        next.isEditing = editingTask != nil
        next.title = draft.title
        next.canSave = !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
        next.activePicker = picker

        if let editingTask, let hours = MoodEngine.hoursOverdue(editingTask, now: .now), hours > 0 {
            next.overdueBanner = "Overdue by \(Self.overdueText(hours: hours))"
        }

        next.hasDate = draft.dueAt != nil
        next.date = draft.dueAt ?? .now

        var selectedDate = TaskEditorBehavior.DateOption.noDate
        var pickLabel = "Pick a date…"
        if let dueAt = draft.dueAt {
            if calendar.isDateInToday(dueAt) {
                selectedDate = .today
            } else if calendar.isDateInTomorrow(dueAt) {
                selectedDate = .tomorrow
            } else {
                selectedDate = .pick
                pickLabel = dueAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
        }
        if picker == .date {
            // The calendar is open - the pick chip is what's being edited.
            selectedDate = .pick
        }
        next.dateOptions = [
            .init(id: TaskEditorBehavior.DateOption.noDate.rawValue, label: "No date"),
            .init(id: TaskEditorBehavior.DateOption.today.rawValue, label: "Today"),
            .init(id: TaskEditorBehavior.DateOption.tomorrow.rawValue, label: "Tomorrow"),
            .init(id: TaskEditorBehavior.DateOption.pick.rawValue, label: pickLabel),
        ]
        next.selectedDateId = selectedDate.rawValue

        next.hasTime = draft.hasTime
        next.time = draft.dueAt ?? .now
        next.timeText = draft.hasTime
            ? (draft.dueAt ?? .now).formatted(date: .omitted, time: .shortened)
            : "Add time"
        next.suggestionChip = suggestionChipState()

        next.priorityOptions = [
            .init(id: TaskPriority.low.rawValue, label: "Low", dot: .custom(Self.lowPriorityDot)),
            .init(id: TaskPriority.med.rawValue, label: "Medium", dot: .warn),
            .init(id: TaskPriority.high.rawValue, label: "High", dot: .danger),
        ]
        next.selectedPriorityId = draft.priority.rawValue

        next.listOptions = [.init(id: Self.inboxId, label: "Inbox", dot: .custom(Color(hexString: TaskListDefaults.colorChoices[0])))]
            + lists.map { .init(id: $0.id, label: $0.name, dot: .custom(Color(hexString: $0.colorHex))) }
        next.selectedListId = draft.listId ?? Self.inboxId

        next.repeatOptions = [.init(id: Self.noRepeatId, label: "None")]
            + TaskRepeat.presets.map { .init(id: $0.freq, label: $0.freq.capitalized) }
            + [.init(id: Self.customRepeatId, label: "Custom")]
        next.selectedRepeatId = draft.repeatRule.map {
            $0.customDays == nil ? $0.freq : Self.customRepeatId
        } ?? Self.noRepeatId
        next.repeatDayOptions = Self.dayChips(for: draft.repeatRule, calendar: calendar)

        next.notes = draft.notes ?? ""
        setUIState(next)
    }

    /// The Sun–Sat toggle row, ordered by the locale's first weekday.
    private static func dayChips(
        for rule: TaskRepeat?,
        calendar: Calendar
    ) -> [TaskEditorBehavior.DayChip] {
        guard case .custom(let days) = rule else { return [] }
        return (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            return TaskEditorBehavior.DayChip(
                id: weekday,
                label: calendar.shortStandaloneWeekdaySymbols[weekday - 1],
                accessibilityLabel: calendar.standaloneWeekdaySymbols[weekday - 1],
                isOn: days.contains(weekday)
            )
        }
    }

    private static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    private static func nextRoundHour(calendar: Calendar = .current) -> Date {
        let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    private static func overdueText(hours: Double) -> String {
        if hours < 1 { return "a moment" }
        if hours < 24 { return "\(Int(hours)) hr" }
        let days = Int(hours / 24)
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}
