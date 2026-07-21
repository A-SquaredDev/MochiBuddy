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

    /// Root of the tab - the Home screen.
    func start() -> AnyView {
        let viewModel = HomeViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            bufferStore: container.comfortBufferStore,
            rewardsStore: container.rewardsStore,
            completionStore: container.taskCompletionStore,
            membershipSession: container.membershipSession,
            recurrenceRoller: container.recurrenceRoller,
            relay: container.notificationOrchestrator,
            reentryService: container.vacationReentryService,
            celebrationCenter: container.celebrationCenter
        )
        return AnyView(HomeView(viewModel: viewModel, router: self))
    }

    /// Lapsed "Wake Mochi" CTA - back through the flow, which recognises
    /// the returning account and lands on the reactivate gate.
    func wakeMochi() {
        container.session.phase = .flow
    }

    /// The add/edit sheet - `draftTitle` seeds a new capture from quick-add.
    func taskEditor(task: TaskItem?, draftTitle: String? = nil) -> AnyView {
        let viewModel = TaskEditorViewModel(
            editingTask: task,
            draftTitle: draftTitle,
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository
        )
        return AnyView(TaskEditorView(viewModel: viewModel))
    }
}
