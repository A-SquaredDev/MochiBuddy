//
//  NotificationPlan.swift
//  MochiBuddy
//
//  The semantic model of a planned local notification. The planner emits
//  these (no copy, no UN* types); the copy library dresses them and the
//  center adapter schedules them. Stable IDs are the contract that lets a
//  re-lay wipe and rewrite mood pings without ever touching a promise.
//

import Foundation

enum NotificationClass: String, Equatable {
    /// Due reminder - user-requested, exact, sacred. Never mood-driven,
    /// never dropped by a mood suppression.
    case promise
    /// Ambient, vague, capped, predicted off the forecast curve.
    case moodPing
    /// The morning briefing - its own class, outside the mood-ping cap.
    case rundown
    /// The repeating safety net for dormant users past the horizon.
    case backstop
    /// The weekly-letter invitation (Feature 3) - never the delivery; the
    /// letter itself arrives in-app on the next eligible foreground.
    case letter
}

/// Weekly letter (Feature 3): the current period's identity + cutoff,
/// handed to the planner only once the period is already NON-DORMANT -
/// the scheduling invariant that never queues a Sunday invitation for
/// someone who may then vanish all week.
struct LetterNotificationInput: Equatable {
    let periodStartDate: String
    let fireAt: Date
}

struct PlannedNotification: Equatable {
    let id: String
    let kind: NotificationClass
    let fireAt: Date
    /// Repeating trigger (recurring-task promise, backstop) - one slot.
    var repeats: Bool = false
    /// Promises: the task this reminds about.
    var taskId: String? = nil
    /// Mood pings: the predicted band baked in at scheduling time. The
    /// consistency invariant: this must equal mood(fireAt) recomputed.
    var band: MoodBand? = nil
}

/// Stable notification identifiers (design doc: Scheduling model).
enum NotificationID {
    static let moodPrefix = "mood-"
    static let duePrefix = "due-"
    static let rundownPrefix = "rundown-"
    static let backstop = "backstop"
    /// Letter ids equal the letter DOCUMENT id ("letter-2026-07-20") so a
    /// tap resolves straight to its archive entry.
    static let letterPrefix = "letter-"

    static func due(taskId: String) -> String {
        "\(duePrefix)\(taskId)"
    }

    static func letter(periodStartDate: String) -> String {
        "\(letterPrefix)\(periodStartDate)"
    }

    /// The letter document id a tapped letter notification names, nil for
    /// every other id.
    static func parseLetter(_ id: String) -> String? {
        id.hasPrefix(letterPrefix) ? id : nil
    }

    static func mood(band: MoodBand, fireAt: Date) -> String {
        "\(moodPrefix)\(band.rawValue)-\(Int(fireAt.timeIntervalSince1970))"
    }

    static func rundown(on day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%@%04d-%02d-%02d",
            rundownPrefix, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// True for IDs a re-lay may wipe (mood pings + backstop). Promises
    /// and rundowns are rewritten by their own stable IDs, never nuked.
    static func isMoodManaged(_ id: String) -> Bool {
        id.hasPrefix(moodPrefix) || id == backstop
    }

    /// Recover the band + fire time baked into a mood-ping id - the dev
    /// inspector's invariant check reads pending ids back through this.
    static func parseMood(_ id: String) -> (band: MoodBand, fireAt: Date)? {
        guard id.hasPrefix(moodPrefix) else { return nil }
        let parts = id.dropFirst(moodPrefix.count).split(separator: "-")
        guard parts.count == 2,
              let raw = Int(parts[0]), let band = MoodBand(rawValue: raw),
              let epoch = TimeInterval(parts[1])
        else { return nil }
        return (band, Date(timeIntervalSince1970: epoch))
    }
}
