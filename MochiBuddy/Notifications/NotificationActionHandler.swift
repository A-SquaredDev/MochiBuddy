//
//  NotificationActionHandler.swift
//  MochiBuddy
//
//  Notification actions run without opening the app (design doc: Actions
//  & richness): Complete removes stress at the source, Snooze pushes the
//  due date and feeds the procrastination counter, Pet bumps the buffer,
//  Shh opens the 24h valve. Every action ends in a re-lay.
//

import Foundation

enum NotificationActionID {
    static let complete = "mochi.action.complete"
    static let pet = "mochi.action.pet"
    static let shh = "mochi.action.shh"
}

@MainActor
final class NotificationActionHandler {

    private let authRepository: AuthRepository
    private let taskRepository: TaskRepository
    private let profileRepository: UserProfileRepository
    private let completionStore: TaskCompletionStore
    private let bufferStore: ComfortBufferStore
    private let orchestrator: NotificationOrchestrator
    private let telemetry: NotificationTelemetry

    init(
        authRepository: AuthRepository,
        taskRepository: TaskRepository,
        profileRepository: UserProfileRepository,
        completionStore: TaskCompletionStore,
        bufferStore: ComfortBufferStore,
        orchestrator: NotificationOrchestrator,
        telemetry: NotificationTelemetry
    ) {
        self.authRepository = authRepository
        self.taskRepository = taskRepository
        self.profileRepository = profileRepository
        self.completionStore = completionStore
        self.bufferStore = bufferStore
        self.orchestrator = orchestrator
        self.telemetry = telemetry
    }

    func handle(actionId: String, notificationId: String) async {
        switch actionId {
        case NotificationActionID.complete:
            await complete(taskId: taskId(from: notificationId))

        case SnoozeOption.oneHour.rawValue, SnoozeOption.tonight.rawValue,
             SnoozeOption.tomorrow.rawValue:
            if let option = SnoozeOption(rawValue: actionId) {
                await snooze(option, taskId: taskId(from: notificationId))
            }

        case NotificationActionID.pet:
            bufferStore.add(lift: TreatCatalog.Pet.lift, duration: TreatCatalog.Pet.duration)
            telemetry.log(.action(name: "pet", band: nil))
            await orchestrator.relayNow(.notificationAction)

        case NotificationActionID.shh:
            telemetry.log(.action(name: "shh", band: nil))
            await orchestrator.activateShh()

        default:
            // Default tap opens the app; the foreground re-lay covers it.
            break
        }
    }

    /// Promises carry their task in the identifier: due-{taskId}.
    private func taskId(from notificationId: String) -> String? {
        guard notificationId.hasPrefix(NotificationID.duePrefix) else { return nil }
        return String(notificationId.dropFirst(NotificationID.duePrefix.count))
    }

    private func complete(taskId: String?) async {
        guard let taskId,
              let userId = authRepository.currentAccount?.uid,
              let task = (try? await taskRepository.task(id: taskId, userId: userId)) ?? nil,
              !task.completed
        else { return }
        let coins = (try? await profileRepository.fetchProfile(userId: userId))?.coins ?? 0
        _ = await completionStore.setCompleted(
            task, completed: true, currentCoins: coins, userId: userId
        )
        telemetry.log(.action(name: "complete", band: nil))
        await orchestrator.relayNow(.notificationAction)
    }

    private func snooze(_ option: SnoozeOption, taskId: String?) async {
        guard let taskId, let userId = authRepository.currentAccount?.uid else { return }
        try? await taskRepository.snoozeTask(
            id: taskId, to: option.targetDate(from: .now), userId: userId
        )
        telemetry.log(.action(name: option.rawValue, band: nil))
        await orchestrator.relayNow(.notificationAction)
    }
}
