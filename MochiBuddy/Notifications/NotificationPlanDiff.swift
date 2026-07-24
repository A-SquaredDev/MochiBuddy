//
//  NotificationPlanDiff.swift
//  MochiBuddy
//
//  A re-lay is a diff, never a nuke-and-rebuild: compare the desired plan
//  against what iOS has pending and produce the minimal change set. Adding
//  with an existing identifier atomically replaces it (no gap in which a
//  reminder could be missed), so the only real risk - removing a promise
//  that should survive - is confined to the removal rule below.
//

import Foundation

struct NotificationPlanDiff: Equatable {
    /// Pending identifiers to cancel: ours, and no longer desired.
    let removeIds: [String]
    /// Everything desired is (re)scheduled - same-id adds replace in place.
    let schedule: [PlannedNotification]
}

enum NotificationPlanDiffer {

    /// Identifiers this app owns. Anything else pending (however it got
    /// there) is never touched.
    static func isOurs(_ id: String) -> Bool {
        id.hasPrefix(NotificationID.duePrefix)
            || id.hasPrefix(NotificationID.moodPrefix)
            || id.hasPrefix(NotificationID.rundownPrefix)
            || id.hasPrefix(NotificationID.letterPrefix)
            || id == NotificationID.backstop
    }

    static func diff(
        desired: [PlannedNotification],
        pendingIds: [String]
    ) -> NotificationPlanDiff {
        let desiredIds = Set(desired.map(\.id))
        let removals = pendingIds.filter { isOurs($0) && !desiredIds.contains($0) }
        return NotificationPlanDiff(removeIds: removals, schedule: desired)
    }
}
