//
//  HomeRouter.swift
//  MochiBuddy
//
//  Builds the Home tab. Home has no pushed destinations yet (the treat
//  shop is a sheet owned by the screen); task detail/edit navigation
//  lands here with the Tasks milestone.
//

import SwiftUI

@MainActor
final class HomeRouter {

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    /// Root of the tab — the Home screen.
    func start() -> AnyView {
        let viewModel = HomeViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            bufferStore: container.comfortBufferStore,
            rewardsStore: container.rewardsStore,
            completionStore: container.taskCompletionStore
        )
        return AnyView(HomeView(viewModel: viewModel, router: self))
    }

    /// The edit sheet for a Today row.
    func taskEditor(task: TaskItem?) -> AnyView {
        let viewModel = TaskEditorViewModel(
            editingTask: task,
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository
        )
        return AnyView(TaskEditorView(viewModel: viewModel))
    }
}
