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
            celebrationCenter: container.celebrationCenter,
            letterService: container.letterCompositionService,
            memoriesService: container.memoriesService
        )
        return AnyView(HomeView(viewModel: viewModel, router: self))
    }

    /// Lapsed "Wake Mochi" CTA - back through the flow, which recognises
    /// the returning account and lands on the reactivate gate.
    func wakeMochi() {
        container.session.phase = .flow
    }

    /// A letter read from Home (envelope or notification tap) - sheet
    /// presentation; the archive's pushed detail lives under You.
    func letterDetail(letter: Letter, source: LetterOpenSource, onClose: @escaping () -> Void) -> AnyView {
        let viewModel = LetterDetailViewModel(
            letter: letter,
            source: source,
            letterService: container.letterCompositionService,
            adoptedOn: container.petIdentityStore.adoptedOn
        )
        return AnyView(LetterDetailView(viewModel: viewModel, onClose: onClose))
    }

    /// The add/edit sheet - `draftTitle` seeds a new capture from quick-add.
    func taskEditor(task: TaskItem?, draftTitle: String? = nil) -> AnyView {
        let viewModel = TaskEditorViewModel(
            editingTask: task,
            draftTitle: draftTitle,
            petName: container.petIdentityStore.name,
            authRepository: container.authRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository
        )
        return AnyView(TaskEditorView(viewModel: viewModel))
    }
}
