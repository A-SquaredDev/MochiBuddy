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
    let membershipStore: MembershipStore
    let notificationPermissionService: NotificationPermissionService
    let remindersGateway: RemindersGateway

    init() {
        let firestore = Firestore.firestore()
        authRepository = FirebaseAuthRepository()
        profileRepository = FirestoreUserProfileRepository(firestore: firestore)
        taskRepository = FirestoreTaskRepository(firestore: firestore)
        // -mochiLocalMembership keeps membership device-local for UI work
        // without touching StoreKit/sandbox.
        membershipStore = ProcessInfo.processInfo.arguments.contains("-mochiLocalMembership")
            ? LocalMembershipStore()
            : RevenueCatMembershipStore()
        notificationPermissionService = UNNotificationPermissionService()
        remindersGateway = EventKitRemindersGateway()
    }
}
