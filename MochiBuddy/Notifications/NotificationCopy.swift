//
//  NotificationCopy.swift
//  MochiBuddy
//
//  Three classes, three non-negotiable voices (design doc: Copy & voice):
//  mood pings are Mochi's blame-free monologue and never name a task;
//  reminders and the rundown always name the task; celebrations celebrate.
//  Floor copy is two pools - acute (day 1-2, gentle and hopeful) and
//  chronic (day 3+, pure presence, zero ask). Emoji live in celebrations
//  only. Ship test for every line: would this make a fragile person at
//  the floor feel worse? If yes, it was cut.
//

import Foundation

/// Round-robin cursor per pool with a built-in "never repeat until the
/// pool cycles" guarantee. Codable so the orchestrator persists rotation
/// across lays.
struct CopyDeck: Codable, Equatable {
    private var cursors: [String: Int] = [:]

    mutating func next(from pool: [String], key: String) -> String {
        guard !pool.isEmpty else { return "" }
        let index = cursors[key] ?? 0
        cursors[key] = (index + 1) % pool.count
        return pool[index % pool.count]
    }
}

enum NotificationCopy {

    struct Content: Equatable {
        var title: String
        var body: String
    }

    /// Which floor pool applies - shifts acute → chronic with the taper.
    enum FloorPhase {
        case acute
        case chronic
    }

    // MARK: - Mood ping pools (never a task name, never a count)

    static let uneasyPool = [
        "Mochi is getting a little fidgety. One small win would settle him right down.",
        "Mochi keeps glancing at the list. Nothing scary, just a nudge.",
        "A tiny task would make Mochi's whole afternoon.",
        "Mochi is doing little pacing circles. He believes in you.",
        "One check-off and Mochi curls right back up.",
        "Mochi noticed something slipping. No rush, whenever you're ready.",
    ]

    static let anxiousPool = [
        "Mochi is having a wobbly moment. He'd love some company.",
        "Mochi is a little tangled up right now. A small step would help you both.",
        "Things feel heavy to Mochi today. Start tiny, he'll follow.",
        "Mochi is chewing on his blanket again. Come sit with the list together.",
        "Mochi is worried, but he knows you always come through.",
        "Deep breaths, says Mochi. One thing at a time.",
    ]

    static let floorAcutePool = [
        "Mochi is having a hard day too. Anything at all lifts you both.",
        "It's been a lot lately. Mochi just wants to see you.",
        "Mochi is sitting with it. One little thing, together?",
        "Even a tiny check-in makes Mochi's day softer.",
        "Rough patch. Mochi is not going anywhere.",
        "Mochi saved you a spot. Whenever you're ready.",
    ]

    static let floorChronicPool = [
        "No pressure. Mochi is just here.",
        "Mochi is keeping your spot warm.",
        "Nothing needed today. Mochi says hi.",
        "Mochi is right where you left him.",
        "Quiet day. Mochi is thinking of you.",
    ]

    /// Celebrations are the one place emoji is allowed.
    static let celebrationPool = [
        "Mochi is doing his happy dance! 🎉",
        "Look at you go. Mochi is beaming.",
        "Mochi squeaked with joy!",
        "That streak though. Mochi is so proud. ✨",
        "Confetti everywhere. Mochi insisted.",
    ]

    // MARK: - Rendering

    static func moodPing(
        band: MoodBand,
        floorPhase: FloorPhase,
        deck: inout CopyDeck
    ) -> Content {
        let (pool, key): ([String], String) = switch band {
        case .verySad:
            floorPhase == .chronic
                ? (floorChronicPool, "floor-chronic")
                : (floorAcutePool, "floor-acute")
        case .anxious: (anxiousPool, "anxious")
        default: (uneasyPool, "uneasy")
        }
        return Content(title: "Mochi", body: deck.next(from: pool, key: key))
    }

    /// Reminders name the task - that is their whole job. The opt-in
    /// lock-screen privacy toggle swaps in the nameless variant.
    static func reminder(taskTitle: String?, hideTaskNames: Bool) -> Content {
        guard let taskTitle, !hideTaskNames else {
            return Content(
                title: "Mochi reminder",
                body: "Something on your list is due now."
            )
        }
        return Content(title: taskTitle, body: "Due now. Mochi is rooting for you.")
    }

    /// Yesterday needs at least this many completions to earn the
    /// "crushed it" beat (Remote Config candidate).
    static let crushedYesterdayThreshold = 5

    /// The morning briefing: tone flexes to the load, length never does.
    /// A notably productive yesterday takes over the title - the no-cost
    /// celebration beat folded in, never a separate ping.
    static func rundown(
        taskTitles: [String],
        hideTaskNames: Bool,
        crushedYesterday: Bool = false
    ) -> Content {
        guard !taskTitles.isEmpty else {
            return Content(
                title: crushedYesterday ? "You crushed yesterday" : "A calm day",
                body: "Nothing due today. Mochi is taking it easy with you."
            )
        }
        let title = if crushedYesterday {
            "You crushed yesterday"
        } else {
            switch taskTitles.count {
            case 1: "One thing today"
            case 2: "A light day today"
            default: "Big one today. We've got this"
            }
        }
        if hideTaskNames {
            let count = taskTitles.count
            return Content(
                title: title,
                body: "Your top \(count) \(count == 1 ? "task is" : "tasks are") ready when you are."
            )
        }
        return Content(title: title, body: taskTitles.joined(separator: " · "))
    }

    static func celebration(deck: inout CopyDeck) -> Content {
        Content(title: "Mochi", body: deck.next(from: celebrationPool, key: "celebration"))
    }
}
