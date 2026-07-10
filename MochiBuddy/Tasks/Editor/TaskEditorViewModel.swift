//
//  TaskEditorViewModel.swift
//  MochiBuddy
//
//  Add & Edit task — the full field set (title, when, priority, list,
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
    private let editingTask: TaskItem?

    // Domain source of truth.
    private var draft: TaskDraft
    private var lists: [TaskList] = []

    init(
        editingTask: TaskItem?,
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository
    ) {
        self.editingTask = editingTask
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
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
            // Fast capture defaults to due today (date-only).
            draft = TaskDraft(title: "", dueAt: Calendar.current.startOfDay(for: .now))
        }
        super.init(initialState: TaskEditorBehavior.UIState())
    }

    override func triggerAsync(_ action: TaskEditorBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId {
                lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
            }
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
            // Only honor the calendar while it's shown — a picker being
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
            state.isWorking = true
            try? await taskRepository.deleteTask(id: task.id, userId: userId)
            setNavigationEvent(.done)

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
            // A custom rule needs at least one day — ignore removing the last.
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
        guard !title.isEmpty, let userId else { return }
        draft.title = title
        state.isWorking = true

        if let task = editingTask {
            var updated = task
            updated.title = draft.title
            updated.notes = draft.notes
            updated.dueAt = draft.dueAt
            updated.hasTime = draft.hasTime
            updated.priority = draft.priority
            updated.listId = draft.listId
            updated.repeatRule = draft.repeatRule
            try? await taskRepository.updateTask(updated, userId: userId)
        } else {
            _ = try? await taskRepository.addTask(draft, userId: userId)
        }
        Haptics.success()
        setNavigationEvent(.done)
    }

    /// Pushes the due date a day forward (design doc: snooze increments the
    /// reschedule counter — the v2 procrastination signal).
    private func snooze() async {
        guard let task = editingTask, let userId else { return }
        let calendar = Calendar.current
        let base = max(task.dueAt ?? .now, calendar.startOfDay(for: .now))
        let newDue = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        state.isWorking = true
        try? await taskRepository.snoozeTask(id: task.id, to: newDue, userId: userId)
        setNavigationEvent(.done)
    }

    // MARK: - Derivation

    private func rebuild(picker: TaskEditorBehavior.PickerTarget) {
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
            // The calendar is open — the pick chip is what's being edited.
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
