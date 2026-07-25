//
//  TasksRouter.swift
//  MochiBuddy
//
//  Builds the Tasks tab, its editor sheet, and the push into Manage lists
//  (shared with the You flow - same screen, this tab's back stack).
//

import SwiftUI

@MainActor
protocol TasksRouting: BackRouting {
    /// The add/edit sheet - `task: nil` means new capture, optionally
    /// seeded with a title (Home quick-add) or a list (ListDetail).
    func taskEditor(task: TaskItem?, draftTitle: String?, draftListId: String?) -> AnyView
    func navigateToManageLists()
    func navigateToListDetail(source: ListDetailSource)
}

extension TasksRouting {
    func taskEditor(task: TaskItem?) -> AnyView {
        taskEditor(task: task, draftTitle: nil, draftListId: nil)
    }
}

@MainActor
final class TasksRouter: TasksRouting {

    private let navController: NavController
    private let container: AppContainer

    init(navController: NavController, container: AppContainer) {
        self.navController = navController
        self.container = container
    }

    /// Root of the tab - the Tasks screen.
    func start() -> AnyView {
        let viewModel = TasksViewModel(
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            profileRepository: container.profileRepository,
            completionStore: container.taskCompletionStore,
            remindersGateway: container.remindersGateway,
            membershipSession: container.membershipSession,
            recurrenceRoller: container.recurrenceRoller,
            relay: container.notificationOrchestrator
        )
        return AnyView(TasksView(viewModel: viewModel, router: self))
    }

    func taskEditor(task: TaskItem?, draftTitle: String?, draftListId: String?) -> AnyView {
        let viewModel = TaskEditorViewModel(
            editingTask: task,
            draftTitle: draftTitle,
            draftListId: draftListId,
            petName: container.petIdentityStore.name,
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            suggestionService: container.suggestionService
        )
        return AnyView(TaskEditorView(viewModel: viewModel))
    }

    func navigateToListDetail(source: ListDetailSource) {
        let viewModel = ListDetailViewModel(
            source: source,
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            profileRepository: container.profileRepository,
            completionStore: container.taskCompletionStore,
            remindersGateway: container.remindersGateway,
            membershipSession: container.membershipSession,
            recurrenceRoller: container.recurrenceRoller,
            relay: container.notificationOrchestrator
        )
        navController.navigate(
            route: AdHocRoute(key: "tasks.listDetail"),
            view: AnyView(ListDetailView(viewModel: viewModel, router: self))
        )
    }

    func navigateToManageLists() {
        let viewModel = ManageListsViewModel(
            authRepository: container.authRepository,
            listRepository: container.listRepository,
            taskRepository: container.taskRepository,
            membershipSession: container.membershipSession,
            petName: container.petIdentityStore.name
        )
        navController.navigate(
            route: AdHocRoute(key: "tasks.lists"),
            view: AnyView(ManageListsView(
                viewModel: viewModel,
                router: self,
                taskEditor: { [weak self] task in
                    self?.taskEditor(task: task) ?? AnyView(EmptyView())
                }
            ))
        )
    }

    func navigateBack() {
        navController.popBackStack()
    }
}
