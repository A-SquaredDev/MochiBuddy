//
//  JournalRouter.swift
//  MochiBuddy
//
//  Builds the Journal tab and owns its pushed destinations - the letter
//  detail reuses Feature 3's dual-mode LetterDetailView (the promised
//  navigation-only handoff; same stable letter ids, new home).
//

import SwiftUI

@MainActor
protocol JournalRouting {
    func navigateToLetter(_ letter: Letter, source: LetterOpenSource)
    func navigateBack()
}

@MainActor
final class JournalRouter: JournalRouting {

    private let navController: NavController
    private let container: AppContainer

    init(navController: NavController, container: AppContainer) {
        self.navController = navController
        self.container = container
    }

    func start() -> AnyView {
        let viewModel = JournalViewModel(
            authRepository: container.authRepository,
            profileRepository: container.profileRepository,
            taskRepository: container.taskRepository,
            listRepository: container.listRepository,
            letterRepository: container.letterRepository,
            momentRepository: container.momentRepository,
            momentWriter: container.momentWriter,
            observationService: container.observationService,
            observationLedger: container.observationLedger,
            membershipSession: container.membershipSession,
            petIdentityStore: container.petIdentityStore,
            letterService: container.letterCompositionService,
            coordinator: container.tabCoordinator,
            telemetry: OSLogJournalTelemetry(),
            calendar: .autoupdatingCurrent
        )
        return AnyView(JournalView(
            viewModel: viewModel,
            router: self,
            coordinator: container.tabCoordinator
        ))
    }

    func navigateToLetter(_ letter: Letter, source: LetterOpenSource) {
        let viewModel = LetterDetailViewModel(
            letter: letter,
            source: source,
            letterService: container.letterCompositionService,
            adoptedOn: container.petIdentityStore.adoptedOn
        )
        navController.navigate(
            route: AdHocRoute(key: "journal.letter.\(letter.id)"),
            view: AnyView(LetterDetailView(viewModel: viewModel, onBack: { [weak self] in
                self?.navigateBack()
            }))
        )
    }

    func navigateBack() {
        navController.popBackStack()
    }
}
