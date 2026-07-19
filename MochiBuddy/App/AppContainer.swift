//
//  AppContainer.swift
//  MochiBuddy
//
//  Composition root - every dependency is created once here and injected
//  (no singleton access anywhere below this).
//

import FirebaseFirestore
import Foundation
import UIKit

@MainActor
final class AppContainer {

    let session = AppSession()
    // Home-screen icon follows the flavor. setAlternateIconName is flaky
    // around app activation: the system cancels it outright until the app
    // is active (NSCocoaErrorDomain 3072) and its alert-token machinery
    // returns transient EAGAIN (NSPOSIXErrorDomain 35) for a while right
    // after foregrounding, so wait for activation and retry patiently.
    // No alternateIconName-equality guard: a half-failed set can leave
    // LaunchServices recording a name SpringBoard never displayed, and the
    // guard would then skip forever. Same-name sets are a system no-op
    // (no alert), so always calling is safe.
    let themeStore = ThemeStore(syncAppIcon: { iconName in
        Task { @MainActor in
            for _ in 0..<50 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard UIApplication.shared.supportsAlternateIcons else { return }
            for attempt in 1...6 {
                do {
                    try await UIApplication.shared.setAlternateIconName(iconName)
                    return
                } catch where attempt < 6 {
                    try? await Task.sleep(for: .seconds(1))
                } catch {
                    // A stale icon beats a crash; log the why and move on.
                    NSLog("Icon sync to '%@' failed: %@", iconName ?? "primary", String(describing: error))
                }
            }
        }
    })

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
