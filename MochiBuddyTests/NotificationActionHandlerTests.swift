//
//  NotificationActionHandlerTests.swift
//  MochiBuddyTests
//
//  Notification actions run with the app closed - each must do its one
//  job against the real stores and end in a re-lay, and malformed or
//  irrelevant identifiers must do nothing at all.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeHandler(
    tasks: [TaskItem] = [],
    completed: [TaskItem] = []
) -> (
    NotificationActionHandler,
    StubTaskRepository,
    StubProfileRepository,
    StubComfortBufferStore,
    RecordingTelemetry,
    NotificationOrchestrator
) {
    let auth = StubAuthRepository()
    let profileRepo = StubProfileRepository()
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = tasks
    taskRepo.completed = completed
    let buffer = StubComfortBufferStore()
    let telemetry = RecordingTelemetry()
    let membership = MembershipSession()
    let orchestrator = NotificationOrchestrator(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
        bufferStore: buffer,
        membershipSession: membership,
        scheduler: StubNotificationScheduler(),
        telemetry: telemetry,
        defaults: UserDefaults(suiteName: "action-tests-\(UUID())")!
    )
    let handler = NotificationActionHandler(
        authRepository: auth,
        taskRepository: taskRepo,
        profileRepository: profileRepo,
        completionStore: TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: membership
        ),
        bufferStore: buffer,
        orchestrator: orchestrator,
        telemetry: telemetry
    )
    return (handler, taskRepo, profileRepo, buffer, telemetry, orchestrator)
}

private func actionNames(_ telemetry: RecordingTelemetry) -> [String] {
    telemetry.events.compactMap {
        if case .action(let name, _) = $0 { return name }
        return nil
    }
}

@Suite("NotificationActionHandler")
@MainActor
struct NotificationActionHandlerTests {

    @Test("Complete from the lock screen persists, pays, logs, and re-lays")
    func completeAction() async {
        let (handler, taskRepo, profileRepo, _, telemetry, _) = makeHandler(
            tasks: [makeTask(id: "t1", dueAt: Dates.hours(-1), hasTime: true)]
        )
        await handler.handle(
            actionId: NotificationActionID.complete, notificationId: "due-t1"
        )

        #expect(taskRepo.setCompletedCalls.first.map { $0.taskId == "t1" && $0.completed } == true)
        #expect(profileRepo.coinDeltas == [RewardsStore.coinsPerTask])
        #expect(actionNames(telemetry) == ["complete"])
        #expect(telemetry.events.contains {
            if case .relaid = $0 { return true } else { return false }
        }, "every action ends in a re-lay")
    }

    @Test("Complete on a mood ping or an already-done task is a no-op")
    func completeGuards() async {
        let (handler, taskRepo, profileRepo, _, _, _) = makeHandler(
            completed: [makeTask(id: "done", completed: true, completedAt: Dates.now)]
        )
        await handler.handle(actionId: NotificationActionID.complete, notificationId: "mood-3-99")
        await handler.handle(actionId: NotificationActionID.complete, notificationId: "due-done")
        await handler.handle(actionId: NotificationActionID.complete, notificationId: "due-missing")

        #expect(taskRepo.setCompletedCalls.isEmpty)
        #expect(profileRepo.coinDeltas.isEmpty)
    }

    @Test("each snooze option pushes the due date forward through the snooze path")
    func snoozeActions() async {
        let (handler, taskRepo, _, _, telemetry, _) = makeHandler(
            tasks: [makeTask(id: "t1", dueAt: Dates.hours(-1), hasTime: true)]
        )
        for option in SnoozeOption.allCases {
            await handler.handle(actionId: option.rawValue, notificationId: "due-t1")
        }

        #expect(taskRepo.snoozeCalls.count == 3)
        #expect(taskRepo.snoozeCalls.allSatisfy { $0.id == "t1" && $0.newDueAt > .now })
        #expect(actionNames(telemetry) == SnoozeOption.allCases.map(\.rawValue))
    }

    @Test("Pet bumps the device-local buffer by the free pet's lift")
    func petAction() async {
        let (handler, _, _, buffer, telemetry, _) = makeHandler()
        await handler.handle(actionId: NotificationActionID.pet, notificationId: "mood-4-123")

        #expect(buffer.boosts.first.map {
            $0.lift == TreatCatalog.Pet.lift && $0.duration == TreatCatalog.Pet.duration
        } == true)
        #expect(actionNames(telemetry) == ["pet"])
    }

    @Test("Shh opens the 24h valve via the orchestrator")
    func shhAction() async {
        let (handler, _, _, _, _, orchestrator) = makeHandler()
        await handler.handle(actionId: NotificationActionID.shh, notificationId: "mood-4-123")
        #expect(orchestrator.shhUntil(now: .now) != nil)
    }

    @Test("the default tap (opening the app) does nothing here - the foreground re-lay owns it")
    func defaultTapIsQuiet() async {
        let (handler, taskRepo, _, buffer, telemetry, _) = makeHandler(
            tasks: [makeTask(id: "t1", dueAt: Dates.hours(-1), hasTime: true)]
        )
        await handler.handle(
            actionId: "com.apple.UNNotificationDefaultActionIdentifier",
            notificationId: "due-t1"
        )
        #expect(taskRepo.setCompletedCalls.isEmpty)
        #expect(buffer.boosts.isEmpty)
        #expect(telemetry.events.isEmpty)
    }
}
