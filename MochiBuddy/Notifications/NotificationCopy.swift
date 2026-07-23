//
//  NotificationCopy.swift
//  MochiBuddy
//
//  Three classes, three non-negotiable voices (design doc: Copy & voice):
//  mood pings are the pet's blame-free monologue and never name a task;
//  reminders and the rundown always name the task; celebrations celebrate.
//  Floor copy is two pools - acute (day 1-2, gentle and hopeful) and
//  chronic (day 3+, pure presence, zero ask). Emoji live in celebrations
//  only. Ship test for every line: would this make a fragile person at
//  the floor feel worse? If yes, it was cut.
//
//  Pet-referential lines route through the one templating helper
//  (Personal Layer, Feature 1): pools hold {name} templates, rendered with
//  the profile's pet name at dress time. Promise (reminder) copy never
//  embeds the pet name - the locked rule that lets renames leave promises
//  untouched by construction. Pronouns stay they/them (pronoun selection
//  is deferred).
//

import Foundation

/// The one templating helper: every pet-referential copy surface inserts
/// the name through here. The name is user content - inserted verbatim,
/// never localized, never case-transformed.
enum PetCopyTemplate {
    static let namePlaceholder = "{name}"

    static func render(_ template: String, petName: String) -> String {
        template.replacingOccurrences(of: namePlaceholder, with: petName)
    }
}

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
        "{name} is getting a little fidgety. One small win would settle them right down.",
        "{name} keeps glancing at the list. Nothing scary, just a nudge.",
        "One tiny task and {name} will glow all afternoon.",
        "{name} is doing little pacing circles. They believe in you.",
        "One check-off and {name} curls right back up.",
        "{name} noticed something slipping. No rush, whenever you're ready.",
    ]

    static let anxiousPool = [
        "{name} is having a wobbly moment. They'd love some company.",
        "{name} is a little tangled up right now. A small step would help you both.",
        "Things feel heavy to {name} today. Start tiny, they'll follow.",
        "{name} is chewing on a blanket corner again. Come sit with the list together.",
        "{name} is worried, but they know you always come through.",
        "Deep breaths, says {name}. One thing at a time.",
    ]

    static let floorAcutePool = [
        "{name} is having a hard day too. Anything at all lifts you both.",
        "It's been a lot lately. {name} just wants to see you.",
        "{name} is sitting with it. One little thing, together?",
        "Even a tiny check-in makes the day softer for {name}.",
        "Rough patch. {name} is not going anywhere.",
        "{name} saved you a spot. Whenever you're ready.",
    ]

    static let floorChronicPool = [
        "No pressure. {name} is just here.",
        "{name} is keeping your spot warm.",
        "Nothing needed today. {name} says hi.",
        "{name} is right where you left them.",
        "Quiet day. {name} is thinking of you.",
    ]

    /// Celebrations are the one place emoji is allowed.
    static let celebrationPool = [
        "{name} is doing a happy dance! 🎉",
        "Look at you go. {name} is beaming.",
        "{name} squeaked with joy!",
        "That streak though. {name} is so proud. ✨",
        "Confetti everywhere. {name} insisted.",
    ]

    // MARK: - Rendering

    static func moodPing(
        band: MoodBand,
        floorPhase: FloorPhase,
        petName: String,
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
        return Content(
            title: petName,
            body: PetCopyTemplate.render(deck.next(from: pool, key: key), petName: petName)
        )
    }

    /// Reminders name the task - that is their whole job. The opt-in
    /// lock-screen privacy toggle swaps in the nameless variant.
    /// Promise copy never embeds the pet name (locked rule): a promise is
    /// never re-laid, so a rename must never need to touch one.
    static func reminder(taskTitle: String?, hideTaskNames: Bool) -> Content {
        guard let taskTitle, !hideTaskNames else {
            return Content(
                title: "Reminder",
                body: "Something on your list is due now."
            )
        }
        return Content(title: taskTitle, body: "Due now. Rooting for you.")
    }

    /// Yesterday needs at least this many completions to earn the
    /// "crushed it" beat. Remote-tunable, set once at launch.
    static var crushedYesterdayThreshold = 5

    /// The morning briefing: tone flexes to the load, length never does.
    /// A notably productive yesterday takes over the title - the no-cost
    /// celebration beat folded in, never a separate ping.
    static func rundown(
        taskTitles: [String],
        hideTaskNames: Bool,
        petName: String,
        crushedYesterday: Bool = false
    ) -> Content {
        guard !taskTitles.isEmpty else {
            return Content(
                title: crushedYesterday ? "You crushed yesterday" : "A calm day",
                body: PetCopyTemplate.render(
                    "Nothing due today. {name} is taking it easy with you.",
                    petName: petName
                )
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

    static func celebration(petName: String, deck: inout CopyDeck) -> Content {
        Content(
            title: petName,
            body: PetCopyTemplate.render(deck.next(from: celebrationPool, key: "celebration"), petName: petName)
        )
    }
}
