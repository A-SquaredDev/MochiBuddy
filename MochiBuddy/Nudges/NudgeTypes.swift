//
//  NudgeTypes.swift
//  MochiBuddy
//
//  Occasional in-app reminders for setup the user skipped in onboarding:
//  notifications, the widget, Apple Reminders import. One banner at a
//  time on Home, generously spaced, retiring once acted on or dismissed
//  enough - "gentle nudges, never nags" applies here doubly. In-app only,
//  never a push.
//

import Foundation

enum NudgeTopic: String, Codable, CaseIterable {
    case notifications
    case widget
    case remindersImport
}

enum NudgeConstants {
    static let schemaVersion = 1
    /// Minimum gap between ANY two nudges - one topic at a time, rarely.
    static let minSpacing: TimeInterval = 5 * 24 * 3600
    /// Minimum gap before the SAME topic shows again.
    static let topicCooldown: TimeInterval = 14 * 24 * 3600
    /// Explicit dismissals before a topic retires for good.
    static let maxDismissals = 2
    /// Total surfacings before a topic retires even without a dismissal.
    static let maxShowsPerTopic = 4
    /// Never nudge in the first sessions - the app should prove itself
    /// before asking for anything.
    static let minAccountAgeDays = 2
}

/// What Home renders and routes - fully dressed by NudgeCenter.
struct NudgeBanner: Equatable {
    enum Action: Equatable {
        /// You tab → Notifications (permission still winnable in-app).
        case openNotificationSettings
        /// iOS Settings - the only road back from a hard denial.
        case openSystemSettings
        case showWidgetHelp
        /// You tab → Apple Reminders import.
        case openAppleReminders
    }

    var topic: NudgeTopic
    var text: String
    var ctaTitle: String
    var action: Action
}
