//
//  NotificationPermissionService.swift
//  MochiBuddy
//
//  Wraps the one-shot iOS notification prompt. The onboarding primer fires
//  this only after the user opts in — we get exactly one shot at the
//  system dialog.
//

import Foundation
import UserNotifications

protocol NotificationPermissionService: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
}

final class UNNotificationPermissionService: NotificationPermissionService {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
