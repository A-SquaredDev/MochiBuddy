//
//  TasksRouter.swift
//  MochiBuddy
//
//  Builds the Tasks tab, its editor sheet, and the push into Manage lists
//  (shared with the You flow — same screen, this tab's back stack).
//

import SwiftUI

@MainActor
protocol TasksRouting: BackRouting {
    /// The add/edit sheet — `task: nil` means new capture.
    func taskEditor(task: TaskItem?) -> AnyView
    func navigateToManageLists()
}

@MainActor
final class TasksRouter: TasksRouting {

    private let navController: NavController
    private let container: AppContainer

    init(navController: NavController, container: AppContainer) {
        self.navController = navController
        self.container = container
    }

    /// Root of the tab — the Tasks screen.
    func start() -> AnyView {
        let viewModel = TasksViewModel(
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            profileRepository: container.profileRepository,
            completionStore: container.taskCompletionStore
        )
        return AnyView(TasksView(viewModel: viewModel, router: self))
    }

    func taskEditor(task: TaskItem?) -> AnyView {
        let viewModel = TaskEditorViewModel(
            editingTask: task,
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository
        )
        return AnyView(TaskEditorView(viewModel: viewModel))
    }

    func navigateToManageLists() {
        let viewModel = ManageListsViewModel(
            authRepository: container.authRepository,
            listRepository: container.listRepository
        )
        navController.navigate(
            route: AdHocRoute(key: "tasks.lists"),
            view: AnyView(ManageListsView(viewModel: viewModel, router: self))
        )
    }

    func navigateBack() {
        navController.popBackStack()
    }
}
