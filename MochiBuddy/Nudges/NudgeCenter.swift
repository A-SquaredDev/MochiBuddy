//
//  NudgeCenter.swift
//  MochiBuddy
//
//  Decides which setup nudge (if any) Home shows this foreground. The
//  decision core is pure and heavily tested; the impure shell gathers
//  live permission and widget state. Priority: notifications > widget >
//  Reminders import - one topic per evaluation.
//

import Foundation
import UserNotifications
import WidgetKit

protocol WidgetInstallDetecting: AnyObject {
    /// nil = detection failed or unknown; never nudge on unknown.
    func isWidgetInstalled() async -> Bool?
}

final class WidgetCenterInstallDetector: WidgetInstallDetecting {
    func isWidgetInstalled() async -> Bool? {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: (try? result.get()).map { !$0.isEmpty })
            }
        }
    }
}

@MainActor
final class NudgeCenter {

    /// Everything the pure core needs, gathered by `evaluate`.
    struct Context: Equatable {
        var notificationStatus: UNAuthorizationStatus
        var widgetInstalled: Bool?
        var remindersConnected: Bool
        var isLapsed: Bool
        var onVacation: Bool
        var accountAgeDays: Int?
    }

    private let ledger: NudgeLedger
    private let permissionService: NotificationPermissionService
    private let widgetDetector: WidgetInstallDetecting
    private let membershipSession: MembershipSession

    init(
        ledger: NudgeLedger,
        permissionService: NotificationPermissionService,
        widgetDetector: WidgetInstallDetecting,
        membershipSession: MembershipSession
    ) {
        self.ledger = ledger
        self.permissionService = permissionService
        self.widgetDetector = widgetDetector
        self.membershipSession = membershipSession
    }

    // MARK: - Pure core

    static func nextTopic(
        context: Context,
        state: NudgeLedger.State,
        now: Date
    ) -> NudgeTopic? {
        guard !context.isLapsed, !context.onVacation else { return nil }
        guard let age = context.accountAgeDays, age >= NudgeConstants.minAccountAgeDays else {
            return nil
        }
        if let last = state.lastNudgeShownAt,
           now.timeIntervalSince(last) < NudgeConstants.minSpacing {
            return nil
        }

        func eligible(_ topic: NudgeTopic) -> Bool {
            let topicState = state.topics[topic.rawValue] ?? NudgeLedger.TopicState()
            guard topicState.actedAt == nil,
                  topicState.dismissCount < NudgeConstants.maxDismissals,
                  topicState.shownCount < NudgeConstants.maxShowsPerTopic
            else { return false }
            if let last = topicState.lastShownAt,
               now.timeIntervalSince(last) < NudgeConstants.topicCooldown {
                return false
            }
            return true
        }

        let needsNotifications = switch context.notificationStatus {
        case .notDetermined, .provisional, .denied: true
        default: false
        }
        if needsNotifications, eligible(.notifications) { return .notifications }
        if context.widgetInstalled == false, eligible(.widget) { return .widget }
        if !context.remindersConnected, eligible(.remindersImport) { return .remindersImport }
        return nil
    }

    // MARK: - Impure shell

    func evaluate(userId: String, profile: UserProfile, now: Date = .now) async -> NudgeBanner? {
        let status = await permissionService.authorizationStatus()
        let context = Context(
            notificationStatus: status,
            widgetInstalled: await widgetDetector.isWidgetInstalled(),
            remindersConnected: !profile.importedReminderListIds.isEmpty,
            isLapsed: membershipSession.isLapsed,
            onVacation: profile.vacationActive(at: now),
            accountAgeDays: profile.createdAt.map {
                Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: $0),
                    to: Calendar.current.startOfDay(for: now)
                ).day ?? 0
            }
        )
        guard let topic = Self.nextTopic(
            context: context, state: ledger.state(userId: userId), now: now
        ) else { return nil }
        return Self.banner(for: topic, status: status, petName: profile.mochiName)
    }

    static func banner(
        for topic: NudgeTopic,
        status: UNAuthorizationStatus,
        petName: String
    ) -> NudgeBanner {
        switch topic {
        case .notifications where status == .denied:
            NudgeBanner(
                topic: .notifications,
                text: "Notifications are off in Settings, so \(petName)'s morning rundown can't reach you.",
                ctaTitle: "Open Settings",
                action: .openSystemSettings
            )
        case .notifications:
            NudgeBanner(
                topic: .notifications,
                text: "Mornings are better with a hello from \(petName). Turn on notifications?",
                ctaTitle: "Turn on",
                action: .openNotificationSettings
            )
        case .widget:
            NudgeBanner(
                topic: .widget,
                text: "Keep \(petName) on your home screen. The widget shows today at a glance.",
                ctaTitle: "Show me",
                action: .showWidgetHelp
            )
        case .remindersImport:
            NudgeBanner(
                topic: .remindersImport,
                text: "Already use Apple Reminders? \(petName) can watch those lists too.",
                ctaTitle: "Connect",
                action: .openAppleReminders
            )
        }
    }

    // MARK: - Ledger pass-throughs

    func recordShown(_ topic: NudgeTopic, userId: String) {
        ledger.recordShown(topic, userId: userId)
    }

    func dismissed(_ topic: NudgeTopic, userId: String) {
        ledger.recordDismissed(topic, userId: userId)
    }

    func acted(_ topic: NudgeTopic, userId: String) {
        ledger.recordActed(topic, userId: userId)
    }
}
