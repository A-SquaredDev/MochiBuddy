//
//  LetterCopy.swift
//  MochiBuddy
//
//  The letter template library (Personal Layer, Feature 3). Mochi's
//  monologue voice in prose: warm, specific, never a report card. No
//  emoji (VoiceOver reads letters aloud), no em dashes.
//
//  The ROUGH set is structurally restricted: those templates carry no
//  interpolation slot other than {name}, no quantities, no task titles,
//  no observations, and no ask (a test asserts the structure; the
//  numeral scan on rendered output is a backstop, not the policy). A bad
//  week's letter proves "sad WITH you, never AT you" at the template
//  level, not by hoping.
//
//  Templates hold a full and a private variant; they differ only where a
//  task title would appear - the private variant is composed from beat
//  data at composition time, never by string surgery on finished prose.
//

import Foundation

/// One letter line in both share variants.
struct LetterTemplate: Equatable {
    let full: String
    let priv: String

    /// Most lines are identical in both variants.
    init(_ shared: String) {
        full = shared
        priv = shared
    }

    init(full: String, priv: String) {
        self.full = full
        self.priv = priv
    }
}

enum LetterCopy {

    /// Stored on every letter as provenance; bump on any pool change.
    static let version = 1

    // MARK: - Salutations

    static let standardSalutations = [
        LetterTemplate("Hey. {name} here, with the week."),
        LetterTemplate("It's {name}. Sunday letter, as promised."),
        LetterTemplate("Hello from {name}. The week deserves a few words."),
    ]

    static let quietSalutations = [
        LetterTemplate("Hey. Just a little note from {name}."),
        LetterTemplate("It's {name}. Short one this week."),
        LetterTemplate("A small hello from {name}."),
    ]

    static let roughSalutations = [
        LetterTemplate("Hey. It's {name}."),
        LetterTemplate("{name} here. Sitting with you a minute."),
        LetterTemplate("Just {name}, checking in softly."),
    ]

    static let vacationSalutations = [
        LetterTemplate("Hey, traveler. {name} here."),
        LetterTemplate("It's {name}, writing from the windowsill."),
        LetterTemplate("Welcome-back notes from {name}."),
    ]

    // MARK: - Optional beats

    /// {milestone} is the spelled-out streak count.
    static let milestonePool = [
        LetterTemplate("{milestone} days together this week. {name} counted every single one."),
        LetterTemplate("You hit {milestone} days of showing up. {name} is still a little giddy about it."),
        LetterTemplate("That {milestone}-day streak landed this week. {name} keeps replaying the moment."),
    ]

    /// The single biggest recovery, named in full; neutral in private.
    static let comebackPool = [
        LetterTemplate(
            full: "{task} had been waiting a while. You got it done {weekday}, and {name} noticed.",
            priv: "Something that had been waiting a while finally got done {weekday}. {name} noticed."
        ),
        LetterTemplate(
            full: "You circled back to {task} this week. {name} loves watching you catch things.",
            priv: "You circled back to a big one you'd been putting off. {name} loves watching you catch things."
        ),
        LetterTemplate(
            full: "{task} finally came off the list {weekday}. {name} did a little spin.",
            priv: "A long-waiting one finally came off the list {weekday}. {name} did a little spin."
        ),
    ]

    /// {weekday} + {count} (spelled) - numbers are welcome outside rough.
    static let bestDayPool = [
        LetterTemplate("{weekday} was a big one. {count} things done, and {name} danced."),
        LetterTemplate("{weekday} carried the week: {count} check-offs. {name} watched the whole show."),
        LetterTemplate("If the week had a headline it was {weekday}. {count} things, one afternoon of glory."),
    ]

    /// Observation beats, per conclusion kind - qualitative, letter register.
    static let observationWeekdayPool = [
        LetterTemplate("Also: {weekday}s are your days. {name} has been keeping notes."),
        LetterTemplate("One more thing {name} noticed: the most gets done on {weekday}s."),
    ]

    static let observationMorningPool = [
        LetterTemplate("Also: mornings are when things happen around here. {name} noticed."),
        LetterTemplate("One more thing: the early hours are yours. {name} has seen it enough to be sure."),
    ]

    static let observationAfternoonPool = [
        LetterTemplate("Also: afternoons are where your day comes together. {name} noticed."),
        LetterTemplate("One more thing: you hit your stride after lunch. {name} keeps notes."),
    ]

    static let observationEveningPool = [
        LetterTemplate("Also: your day comes together in the evening. {name} noticed."),
        LetterTemplate("One more thing: you wind the day down by getting things done. {name} admires it."),
    ]

    /// The night band affirms, never corrects.
    static let observationNightPool = [
        LetterTemplate("Also: the late hours are yours, and that counts just the same. {name} noticed."),
        LetterTemplate("One more thing: night is when your list gets shorter. {name} keeps you company either way."),
    ]

    static let observationMomentumPool = [
        LetterTemplate("Also: more check-offs lately. {name} can feel it."),
        LetterTemplate("One more thing: something's picked up around here. {name} noticed."),
    ]

    static let observationComebackPool = [
        LetterTemplate("Also: when something slips, you catch it fast. {name} loves that about you."),
        LetterTemplate("One more thing: slipped things don't stay slipped around you. {name} keeps notes."),
    ]

    /// Celebrates the return; never references the absence.
    static let listReturnPool = [
        LetterTemplate("You found your way back to {list} this week. {name} was glad to see it."),
        LetterTemplate("{list} got some love this week. {name} likes seeing that one move."),
    ]

    // MARK: - Structural beats

    /// Rough register: chronic-floor voice, zero ask, {name} only.
    static let presencePool = [
        LetterTemplate("This week was heavy, and there is nothing you need to explain. {name} stayed close through all of it, and stays close still."),
        LetterTemplate("It was a lot this week. {name} isn't going anywhere, not tonight, not tomorrow, not any of the days after that."),
        LetterTemplate("Some weeks just weigh more than others. {name} sat with you through every one of this week's heavier hours, and would again."),
    ]

    /// The rough letter's only second beat: one small true positive,
    /// no quantities, no titles, no ask.
    static let smallTruePositivePool = [
        LetterTemplate("And still, you showed up where it mattered. {name} saw every bit of it, and it counted for a great deal."),
        LetterTemplate("Even so, things got done this week. {name} watched each one land, quietly and with enormous pride."),
        LetterTemplate("You kept things moving anyway, which is the hard version of moving. {name} thinks that counts double, at least."),
    ]

    static let vacationPool = [
        LetterTemplate("You were away, and resting counts. {name} kept the porch light on."),
        LetterTemplate("Part of this week was yours to rest. {name} thinks that was exactly right."),
        LetterTemplate("You stepped away for a bit. {name} saved your spot and napped in it a little."),
    ]

    /// The quiet letter's only beat - a couple of cozy sentences, zero ask.
    static let quietPool = [
        LetterTemplate("Not much stirred this week, and that was completely fine. {name} liked the quiet company, napped in every sunbeam the apartment offered, and wants you to know that slow weeks count as weeks too."),
        LetterTemplate("A slow week around here. {name} spent most of it curled up somewhere within earshot of you, which as far as {name} is concerned is its own kind of good week, maybe the best kind."),
        LetterTemplate("The list stayed small and the days stayed soft. {name} has no complaints to file, only a slightly flatter cushion and a strong opinion that quiet weeks deserve letters too."),
    ]

    // MARK: - Closings

    static let standardClosings = [
        LetterTemplate("That's the week as {name} saw it. Same windowsill, same company, next Sunday and every one after."),
        LetterTemplate("More next Sunday. {name} is already looking forward to writing it, and to all the days before it."),
        LetterTemplate("Until next week. {name} is keeping your spot warm, the way it always has been kept."),
    ]

    static let quietClosings = [
        LetterTemplate("That's all there was, and all there needed to be. {name} is here whenever."),
        LetterTemplate("Short and sweet, like the week itself. {name} sends a nap's worth of calm."),
        LetterTemplate("More when there's more. {name} is around, same spot as always."),
    ]

    static let roughClosings = [
        LetterTemplate("No asks this week. {name} is just here, same as always, for as long as it takes."),
        LetterTemplate("Nothing is needed from you right now. {name} stays either way, and always will."),
        LetterTemplate("That is all this week asked of a letter. {name} is close by whenever you look up."),
    ]

    /// Signature: from the pet-name snapshot, forever.
    static let signature = "From {name}"

    // MARK: - Register lookups

    static func salutations(for classification: LetterClassification) -> [LetterTemplate] {
        switch classification {
        case .quiet: quietSalutations
        case .rough: roughSalutations
        case .vacationPartial: vacationSalutations
        case .great, .steady: standardSalutations
        }
    }

    static func closings(for classification: LetterClassification) -> [LetterTemplate] {
        switch classification {
        case .quiet: quietClosings
        case .rough: roughClosings
        case .great, .steady, .vacationPartial: standardClosings
        }
    }

    static func observationPool(for conclusion: ObservationConclusion) -> [LetterTemplate] {
        switch conclusion {
        case .weekday: observationWeekdayPool
        case .band(.morning): observationMorningPool
        case .band(.afternoon): observationAfternoonPool
        case .band(.evening): observationEveningPool
        case .band(.night): observationNightPool
        case .momentumRising: observationMomentumPool
        case .comeback: observationComebackPool
        case .listReturn: listReturnPool
        }
    }

    /// Every pool a rough letter may draw from - the restricted set the
    /// structural test asserts over: {name} is the only slot, no digits,
    /// no question marks (no ask).
    static var roughRestrictedPools: [[LetterTemplate]] {
        [roughSalutations, presencePool, smallTruePositivePool, roughClosings]
    }

    // MARK: - Numbers as words

    /// Letters spell small numbers ("Six things done"); larger values fall
    /// back to numerals, which only ever appear outside rough letters.
    static func numberWord(_ value: Int) -> String {
        let small = [
            "zero", "one", "two", "three", "four", "five", "six", "seven",
            "eight", "nine", "ten", "eleven", "twelve", "thirteen",
            "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
            "nineteen", "twenty",
        ]
        if small.indices.contains(value) { return small[value] }
        let tens = [30: "thirty", 40: "forty", 50: "fifty", 60: "sixty",
                    70: "seventy", 80: "eighty", 90: "ninety", 100: "one hundred"]
        return tens[value] ?? "\(value)"
    }
}
