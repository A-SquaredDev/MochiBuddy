//
//  UNNotificationScheduler.swift
//  MochiBuddy
//
//  The thin adapter under NotificationScheduling: maps the dressed
//  request onto UNUserNotificationCenter and nothing else. All decisions
//  were made (and tested) upstream.
//
//  Also owns category registration and the center delegate: actions route
//  to the handler, and foreground presentation keeps ambient pings quiet
//  while Mochi is right there on screen.
//

import Foundation
import UserNotifications

final class UNNotificationScheduler: NotificationScheduling {

    private let center = UNUserNotificationCenter.current()

    func pendingIds() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func pendingRequests() async -> [PendingNotificationSummary] {
        await center.pendingNotificationRequests().map { request in
            let fireDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            return PendingNotificationSummary(id: request.identifier, nextFireDate: fireDate)
        }
    }

    func removePending(ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func schedule(_ request: ScheduledNotificationRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.content.title
        content.body = request.content.body
        content.interruptionLevel = switch request.urgency {
        case .timeSensitive: .timeSensitive
        case .active: .active
        case .passive: .passive
        }
        if let categoryId = request.categoryId {
            content.categoryIdentifier = categoryId
        }
        if let threadId = request.threadId {
            content.threadIdentifier = threadId
        }

        let trigger: UNNotificationTrigger
        if let components = request.repeatingComponents {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else {
            let interval = request.plan.fireAt.timeIntervalSinceNow
            guard interval > 1 else { return } // the moment passed mid-lay
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: interval, repeats: request.plan.repeats
            )
        }

        try? await center.add(UNNotificationRequest(
            identifier: request.plan.id, content: content, trigger: trigger
        ))
    }
}

enum NotificationCategories {

    /// Register once at startup so actions work from a cold start.
    static func register(in center: UNUserNotificationCenter = .current()) {
        let reminder = UNNotificationCategory(
            identifier: NotificationCategoryID.reminder,
            actions: [
                UNNotificationAction(
                    identifier: NotificationActionID.complete, title: "Complete", options: []
                ),
            ] + SnoozeOption.allCases.map {
                UNNotificationAction(identifier: $0.rawValue, title: "Snooze · \($0.title)", options: [])
            },
            intentIdentifiers: []
        )
        let moodPing = UNNotificationCategory(
            identifier: NotificationCategoryID.moodPing,
            actions: [
                UNNotificationAction(
                    identifier: NotificationActionID.pet, title: "Pet Mochi", options: []
                ),
                UNNotificationAction(
                    identifier: NotificationActionID.shh, title: "Mochi, shh · 24h", options: []
                ),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([reminder, moodPing])
    }
}

final class MochiNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Set by the container once the handler graph exists.
    var actionHandler: NotificationActionHandler?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await actionHandler?.handle(
            actionId: response.actionIdentifier,
            notificationId: response.notification.request.identifier
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // With the app open, Mochi's mood is live on screen - ambient
        // pings stay silent; promises still banner (they're exact).
        notification.request.identifier.hasPrefix(NotificationID.duePrefix)
            ? [.banner, .sound]
            : []
    }
}
