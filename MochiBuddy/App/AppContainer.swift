//
//  AppContainer.swift
//  MochiBuddy
//
//  Composition root — every dependency is created once here and injected
//  (no singleton access anywhere below this).
//

import Foundation
import FirebaseFirestore

@MainActor
final class AppContainer {

    let session = AppSession()
    let themeStore = ThemeStore()

    let authRepository: AuthRepository
    let profileRepository: UserProfileRepository
    let taskRepository: TaskRepository
    let listRepository: ListRepository
    let accountEraser: AccountEraser
    let membershipStore: MembershipStore
    let notificationPermissionService: NotificationPermissionService
    let remindersGateway: RemindersGateway
    let comfortBufferStore: ComfortBufferStore
    let rewardsStore: RewardsStore
    let taskCompletionStore: TaskCompletionStore

    init() {
        let firestore = Firestore.firestore()
        authRepository = FirebaseAuthRepository()
        profileRepository = FirestoreUserProfileRepository(firestore: firestore)
        taskRepository = FirestoreTaskRepository(firestore: firestore)
        listRepository = FirestoreListRepository(firestore: firestore)
        accountEraser = FirestoreAccountEraser(firestore: firestore)
        // -mochiLocalMembership keeps membership device-local for UI work
        // without touching StoreKit/sandbox.
        membershipStore = ProcessInfo.processInfo.arguments.contains("-mochiLocalMembership")
            ? LocalMembershipStore()
            : RevenueCatMembershipStore()
        notificationPermissionService = UNNotificationPermissionService()
        remindersGateway = EventKitRemindersGateway()
        comfortBufferStore = UserDefaultsComfortBufferStore()
        rewardsStore = RewardsStore(profileRepository: profileRepository)
        taskCompletionStore = TaskCompletionStore(taskRepository: taskRepository, rewardsStore: rewardsStore)

        // -mochiStartAtHome skips the flow for UI work on the tab surfaces
        // (pair with "-mochiStartTab you|tasks" to land on a specific tab).
        if ProcessInfo.processInfo.arguments.contains("-mochiStartAtHome") {
            session.phase = .home
        }
    }
}
