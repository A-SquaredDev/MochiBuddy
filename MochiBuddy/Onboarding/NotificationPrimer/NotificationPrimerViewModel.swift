//
//  NotificationPrimerViewModel.swift
//  MochiBuddy
//
//  6 · Notification primer — we control this screen and only fire the real
//  iOS prompt if the user says yes (one shot at the system dialog).
//

import Foundation
import UserNotifications

final class NotificationPrimerViewModel: ObservableStateViewModel<
    NotificationPrimerBehavior.UIState,
    NotificationPrimerBehavior.ViewAction,
    NotificationPrimerBehavior.NavigationEvent
> {

    private let permissionService: NotificationPermissionService
    private let onboardingStore: OnboardingStore

    init(permissionService: NotificationPermissionService, onboardingStore: OnboardingStore) {
        self.permissionService = permissionService
        self.onboardingStore = onboardingStore
        super.init(initialState: NotificationPrimerBehavior.UIState())
    }

    override func triggerAsync(_ action: NotificationPrimerBehavior.ViewAction) async {
        switch action {
        case .enableTapped:
            // Only fire the system dialog when it can actually appear;
            // already-decided permission just records the choice and moves on.
            switch await permissionService.authorizationStatus() {
            case .notDetermined:
                state.isRequesting = true
                let granted = await permissionService.requestAuthorization()
                await onboardingStore.saveNotificationChoice(granted: granted)
                state.isRequesting = false
            case .denied:
                await onboardingStore.saveNotificationChoice(granted: false)
            default:
                await onboardingStore.saveNotificationChoice(granted: true)
            }
            setNavigationEvent(.next)

        case .laterTapped:
            await onboardingStore.saveNotificationChoice(granted: false)
            setNavigationEvent(.next)
        }
    }
}
