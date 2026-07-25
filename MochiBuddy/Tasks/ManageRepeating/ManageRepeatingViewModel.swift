//
//  ManageRepeatingViewModel.swift
//  MochiBuddy
//
//  Repeating tasks - every live series in one place, tap to adjust its
//  rule in the task editor. Reached from the Upcoming segment.
//

import Foundation

final class ManageRepeatingViewModel: StateViewModel<
    ManageRepeatingBehavior.UIState,
    ManageRepeatingBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository

    // Domain source of truth.
    private var repeatingTasks: [TaskItem] = []

    init(
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        petName: String = "Mochi"
    ) {
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        var initial = ManageRepeatingBehavior.UIState()
        initial.petName = petName
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: ManageRepeatingBehavior.ViewAction) async {
        switch action {
        case .load:
            await reload()

        case .seriesTapped(let id):
            guard let task = repeatingTasks.first(where: { $0.id == id }) else { return }
            state.editingSeries = ManageRepeatingBehavior.EditingSeries(task: task)

        case .seriesEditorDismissed:
            state.editingSeries = nil
            await reload()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func reload() async {
        guard let userId else { return }
        let tasks = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        repeatingTasks = tasks
            .filter { $0.repeatRule != nil }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        state.series = repeatingTasks.compactMap { task in
            guard let rule = task.repeatRule else { return nil }
            return ManageRepeatingBehavior.RepeatingUIItem(
                id: task.id,
                title: task.title,
                cadence: Self.cadenceText(rule)
            )
        }
    }

    private static func cadenceText(_ rule: TaskRepeat, calendar: Calendar = .current) -> String {
        switch rule {
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .custom(let days):
            days.sorted()
                .map { calendar.shortStandaloneWeekdaySymbols[$0 - 1] }
                .joined(separator: " · ")
        }
    }
}
