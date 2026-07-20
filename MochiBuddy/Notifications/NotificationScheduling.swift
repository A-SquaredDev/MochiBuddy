//
//  NotificationScheduling.swift
//  MochiBuddy
//
//  The seam between the pure scheduler and UNUserNotificationCenter: a
//  fully-dressed request in, side effects out. Everything above this
//  protocol is deterministic and tested; the UN adapter below it stays
//  too thin to be wrong.
//

import Foundation

/// Interruption levels, platform-neutral (design doc: reminders are
/// time-sensitive, mood pings never punch through Focus, the rest is
/// ordinary).
enum NotificationUrgency: String, Equatable {
    case timeSensitive
    case active
    case passive
}

/// Action-set identifiers registered with the system once at startup.
enum NotificationCategoryID {
    /// Complete + the snooze menu.
    static let reminder = "mochi.reminder"
    /// Pet + "Mochi, shh".
    static let moodPing = "mochi.moodPing"
}

/// Everything the notification center needs for one request.
struct ScheduledNotificationRequest: Equatable {
    let plan: PlannedNotification
    let content: NotificationCopy.Content
    let urgency: NotificationUrgency
    let categoryId: String?
    /// Coalescing thread - mood pings share one so they stack politely.
    let threadId: String?
    /// Repeating calendar pattern for recurring promises; nil schedules
    /// the single next fire.
    var repeatingComponents: DateComponents? = nil
}

/// A pending request as the system reports it - the dev inspector's raw
/// material for slot accounting and the invariant check.
struct PendingNotificationSummary: Equatable {
    let id: String
    let nextFireDate: Date?
}

protocol NotificationScheduling: AnyObject {
    func pendingIds() async -> [String]
    func pendingRequests() async -> [PendingNotificationSummary]
    func removePending(ids: [String])
    func schedule(_ request: ScheduledNotificationRequest) async
}

/// Dresses a planned notification in copy + delivery semantics. Pure, so
/// voice rules (mood pings nameless, reminders named, privacy toggle) are
/// unit-testable without the notification center.
enum NotificationRequestBuilder {

    static func request(
        for plan: PlannedNotification,
        tasksById: [String: TaskItem],
        allTasks: [TaskItem],
        completionTimes: [Date] = [],
        floorPhase: NotificationCopy.FloorPhase,
        hideTaskNames: Bool,
        deck: inout CopyDeck,
        calendar: Calendar = .current
    ) -> ScheduledNotificationRequest {
        switch plan.kind {
        case .promise:
            let task = plan.taskId.flatMap { tasksById[$0] }
            let repeating = task?.repeatRule.flatMap { rule in
                PromiseTriggerBuilder.repeatingComponents(
                    for: rule, dueAt: plan.fireAt, calendar: calendar
                )
            }
            return ScheduledNotificationRequest(
                plan: plan,
                content: NotificationCopy.reminder(taskTitle: task?.title, hideTaskNames: hideTaskNames),
                urgency: .timeSensitive,
                categoryId: NotificationCategoryID.reminder,
                threadId: nil,
                repeatingComponents: repeating
            )

        case .moodPing:
            return ScheduledNotificationRequest(
                plan: plan,
                content: NotificationCopy.moodPing(
                    band: plan.band ?? .uneasy, floorPhase: floorPhase, deck: &deck
                ),
                urgency: .passive,
                categoryId: NotificationCategoryID.moodPing,
                threadId: "mochi.mood"
            )

        case .rundown:
            let top = RundownRanker.topTasks(from: allTasks, at: plan.fireAt, calendar: calendar)
            // "Yesterday" relative to the briefing: completions known at
            // lay time on the prior calendar day. Pessimistic like the
            // forecast - future completions can only add, and adding
            // re-lays.
            let yesterdayCount = calendar.date(byAdding: .day, value: -1, to: plan.fireAt)
                .map { yesterday in
                    completionTimes.count { calendar.isDate($0, inSameDayAs: yesterday) }
                } ?? 0
            return ScheduledNotificationRequest(
                plan: plan,
                content: NotificationCopy.rundown(
                    taskTitles: top.map(\.title),
                    hideTaskNames: hideTaskNames,
                    crushedYesterday: yesterdayCount >= NotificationCopy.crushedYesterdayThreshold
                ),
                urgency: .active,
                categoryId: nil,
                threadId: nil
            )

        case .backstop:
            // The dormant-user safety net reads like a chronic-floor line:
            // pure presence, no ask, safe at any staleness.
            return ScheduledNotificationRequest(
                plan: plan,
                content: NotificationCopy.moodPing(band: .verySad, floorPhase: .chronic, deck: &deck),
                urgency: .passive,
                categoryId: NotificationCategoryID.moodPing,
                threadId: "mochi.mood"
            )
        }
    }
}
