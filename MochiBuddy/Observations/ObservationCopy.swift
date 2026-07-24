//
//  ObservationCopy.swift
//  MochiBuddy
//
//  Copy pools for the observation surfaces (Personal Layer, Feature 4).
//  Register: attention, not measurement - "{name} noticed", never "your
//  average" or a percentage. Observation lines are qualitative by locked
//  rule: no counts, no numbers, ever. The night band never implies the
//  schedule is wrong; list-return copy celebrates the return and never
//  references the absence that preceded it. Ship test for every line:
//  would this make someone at the floor feel worse?
//
//  Pools rotate through the shared CopyDeck mechanics ({name} templated
//  via the Feature 1 helper); the ledger persists rotation state.
//

import Foundation

enum ObservationCopy {

    static let weekdayNames = [
        "", "Sundays", "Mondays", "Tuesdays", "Wednesdays",
        "Thursdays", "Fridays", "Saturdays",
    ]

    static let weekdayPool = [
        "You get the most done on {weekday}. {name} noticed.",
        "{weekday} are your days. {name} keeps notes on these things.",
        "Something about {weekday} suits you. {name} has been paying attention.",
        "{name} thinks of {weekday} as your day now.",
    ]

    static let morningPool = [
        "Mornings are when things happen around here. {name} noticed.",
        "You and mornings get along. {name} keeps notes.",
        "The early hours are yours. {name} has seen it enough to be sure.",
        "{name} noticed the day's wins tend to come early.",
    ]

    static let afternoonPool = [
        "Afternoons are when things happen around here. {name} noticed.",
        "You hit your stride after lunch. {name} keeps notes.",
        "The middle of the day is yours. {name} has seen it enough to be sure.",
        "{name} noticed the afternoon is where your day comes together.",
    ]

    static let eveningPool = [
        "Evenings are when things happen around here. {name} noticed.",
        "You wind the day down by getting things done. {name} keeps notes.",
        "The evening is yours. {name} has seen it enough to be sure.",
        "{name} noticed your day comes together in the evening.",
    ]

    /// The night band affirms and never corrects - a night-shift rhythm
    /// is a rhythm, full stop.
    static let nightPool = [
        "Things get done after 9pm around here, and that counts just the same. {name} noticed.",
        "The late hours are yours. {name} thinks that's a fine time for them.",
        "{name} noticed the quiet hours are when you get things done. No notes, just admiration.",
        "Night is when your list gets shorter. {name} keeps you company either way.",
    ]

    static let momentumPool = [
        "More check-offs lately. {name} can feel it.",
        "Things are moving around here. {name} noticed.",
        "{name} can tell something's picked up lately.",
        "The list has been shrinking faster. {name} is quietly delighted.",
    ]

    /// Celebrates the return; the absence is never mentioned.
    static let listReturnPool = [
        "You found your way back to {list} this week. {name} noticed.",
        "{list} got some attention this week. {name} was glad to see it.",
        "Back to {list} this week. {name} likes seeing that one move.",
        "{name} noticed {list} moving again this week.",
    ]

    static let comebackPool = [
        "When something slips, you catch it fast. {name} loves that about you.",
        "{name} noticed you always circle back. It never takes you long.",
        "Slipped things don't stay slipped around you. {name} keeps notes.",
        "You have a way of catching things quickly. {name} admires it.",
    ]

    /// The pool + rotation key for a conclusion.
    static func pool(for conclusion: ObservationConclusion) -> (lines: [String], key: String) {
        switch conclusion {
        case .weekday:
            (weekdayPool, "obs-weekday")
        case .band(.morning):
            (morningPool, "obs-morning")
        case .band(.afternoon):
            (afternoonPool, "obs-afternoon")
        case .band(.evening):
            (eveningPool, "obs-evening")
        case .band(.night):
            (nightPool, "obs-night")
        case .momentumRising:
            (momentumPool, "obs-momentum")
        case .listReturn:
            (listReturnPool, "obs-list-return")
        case .comeback:
            (comebackPool, "obs-comeback")
        }
    }

    /// Renders the next line for a conclusion. `listName` is required
    /// only for list-return conclusions; a missing name yields nil rather
    /// than broken copy.
    static func line(
        for conclusion: ObservationConclusion,
        petName: String,
        listName: String? = nil,
        deck: inout CopyDeck
    ) -> String? {
        let (lines, key) = pool(for: conclusion)
        var template = deck.next(from: lines, key: key)

        switch conclusion {
        case .weekday(let weekday):
            guard weekdayNames.indices.contains(weekday), weekday >= 1 else { return nil }
            template = template.replacingOccurrences(of: "{weekday}", with: weekdayNames[weekday])
        case .listReturn:
            guard let listName else { return nil }
            template = template.replacingOccurrences(of: "{list}", with: listName)
        default:
            break
        }
        return PetCopyTemplate.render(template, petName: petName)
    }
}
