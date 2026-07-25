//
//  MemoriesCopy.swift
//  MochiBuddy
//
//  Rundown and banner copy for anniversaries and memory callbacks
//  (Personal Layer, Feature 2). Qualitative by locked rule where the
//  rule says so: coarse relative time in rundown lines ("a couple of
//  weeks ago"), precise dates reserved for letters. Counts are
//  permitted in the best-day and date-echo families - NEVER in the
//  recovery family, whose templates are structurally restricted (no
//  count slots, no magnitude comparison, no "back to" / "used to" /
//  "back when", "again" only on resilience, no reference to the
//  present pile). The restriction lives in what the templates CAN say,
//  asserted by test, same mechanism as the rough-letter pools.
//
//  Every pool is a {name} template through PetCopyTemplate; rotation
//  rides the CallbackLedger's own CopyDeck.
//

import Foundation

enum MemoriesCopy {

    // MARK: - Anniversary lines ({span} = "One week" / "One month" / "One year" / "Two years")

    static let anniversaryRundownPool = [
        "{span} with {name} today.",
        "Today makes {span} of you and {name}.",
        "{span} together as of today. {name} kept count.",
        "{span} since you and {name} met.",
    ]

    /// The past-tense acknowledgment for a mark passed on vacation -
    /// honest about the date, warm about the moment. {mark} = "one-month"
    /// style adjective form.
    static let deferredAnniversaryPool = [
        "While you were away, you and {name} passed the {mark} mark.",
        "Somewhere out there, you and {name} crossed the {mark} mark.",
        "The {mark} mark slipped by during your time away. {name} counted it anyway.",
        "You and {name} passed the {mark} mark while you were off resting.",
    ]

    static let anniversaryBannerPool = [
        "{span} with {name} today.",
        "{span} of you and {name}. Happy day.",
        "Today marks {span} together. {name} is glowing.",
        "{span}, as of today. {name} remembered the date.",
    ]

    // MARK: - Callback pools

    /// {when} coarse relative time, {count} spelled count. The neutral
    /// lines make no superlative claim, so ties stay honest; the one
    /// {scale} line resolves to "your biggest day" or "one of your
    /// biggest days".
    static let bestDayCallbackPool = [
        "{when} you cleared {count} things in one day. {name} still talks about it.",
        "{name} remembers {scale}: {count} things, one day, {when}.",
        "Remember {when}, when {count} things got done in a single day? {name} does.",
        "{count} in one day, {when}. {name} filed it under favorite memories.",
    ]

    /// STRUCTURALLY RESTRICTED: {name} is the only slot. No digits, no
    /// past-versus-current magnitude, no "back to" / "used to" / "back
    /// when", "again" only on resilience, no question marks, and no
    /// reference to the present pile - the user knows why the line is
    /// showing up; Mochi just believes in them.
    static let recoveryCallbackPool = [
        "You've found your way through a pile before. {name} remembers.",
        "You've dug out before. {name} never doubted it.",
        "There was a stretch that looked heavy, and you cleared it. {name} keeps that story.",
        "You've done this before. {name} was there for it.",
        "{name} has watched you climb out before. That memory stays.",
    ]

    /// {count} spelled record count.
    static let streakEraCountPool = [
        "Your longest run with {name} is {count} days.",
        "{count} days in a row, once. {name} still brags about it.",
        "The record stands at {count} days together. {name} keeps it polished.",
        "{count} straight days, your best yet. {name} remembers every one.",
    ]

    /// Era phrasing - only with a stamped bestStreakAchievedOn. {when}
    /// coarse relative time of the record.
    static let streakEraDatedPool = [
        "Your longest run together, {count} days, wrapped up {when}. {name} was there for all of it.",
        "{when} you set the record: {count} days straight. {name} still talks about that stretch.",
        "The {count}-day record you set {when} still stands. {name} guards it proudly.",
        "{count} days in a row, {when}. {name} calls it the golden stretch.",
    ]

    /// {monthsago} = "A month" / "Two months"...; {count} spelled.
    /// Never "cleared your whole list" - completion records prove
    /// counts, not that the open list was empty.
    static let dateEchoCallbackPool = [
        "{monthsago} ago today you finished {count} things. {name} remembers the date.",
        "{monthsago} ago today, {count} things done. {name} circled it on the calendar.",
        "{monthsago} ago today you had one of those days: {count} finished.",
        "{name} keeps an eye on dates. {monthsago} ago today: {count} things, done and dusted.",
    ]

    /// The structural-restriction test iterates these - extend the list
    /// if another count-free family is ever added.
    static var restrictedPools: [[String]] {
        [recoveryCallbackPool]
    }

    // MARK: - Slot values

    /// "One week" / "One month" / "One year" / "Two years". Every pool
    /// places {span} where the capitalized form reads naturally, so one
    /// form serves all lines.
    static func span(for tier: AnniversaryTier) -> String {
        switch tier {
        case .week: "One week"
        case .month: "One month"
        case .year(1): "One year"
        case .year(let n): "\(LetterCopy.numberWord(n).capitalized) years"
        }
    }

    /// Adjective form for "the {mark} mark".
    static func mark(for tier: AnniversaryTier) -> String {
        switch tier {
        case .week: "one-week"
        case .month: "one-month"
        case .year(1): "one-year"
        case .year(let n): "\(LetterCopy.numberWord(n))-year"
        }
    }

    /// Coarse relative time - deliberately fuzzy so a line laid tonight
    /// is still true at tomorrow's wake.
    static func coarseWhen(daysAgo: Int) -> String {
        switch daysAgo {
        case ..<11: "about a week ago"
        case 11..<21: "a couple of weeks ago"
        case 21..<45: "about a month ago"
        case 45..<75: "a couple of months ago"
        default: "a while back"
        }
    }

    static func monthsAgo(_ months: Int) -> String {
        months == 1 ? "A month" : "\(LetterCopy.numberWord(months).capitalized) months"
    }

    // MARK: - Rendering

    /// The rundown opener TEMPLATE for an assigned Personal-Layer line:
    /// every slot resolved except {name}, which stays for dress time -
    /// so a stored line survives a pet rename (petIdentityChange
    /// re-renders with the live name without burning rotation). Nil for
    /// kinds that render elsewhere (crushed-yesterday keeps its title
    /// override; observations render through ObservationCopy).
    static func rundownOpenerTemplate(
        for line: PersonalLayerLine,
        today: CivilDay,
        deck: inout CopyDeck
    ) -> String? {
        switch line {
        case .crushedYesterday, .observation:
            return nil

        case .anniversary(let milestone):
            return deck.next(from: anniversaryRundownPool, key: "ann-rundown")
                .replacingOccurrences(of: "{span}", with: span(for: milestone.tier))

        case .deferredAnniversary(let milestone):
            return deck.next(from: deferredAnniversaryPool, key: "ann-deferred")
                .replacingOccurrences(of: "{mark}", with: mark(for: milestone.tier))

        case .callback(let fact):
            return callbackLineTemplate(for: fact, today: today, deck: &deck)
        }
    }

    static func callbackLineTemplate(
        for fact: CallbackFact,
        today: CivilDay,
        deck: inout CopyDeck
    ) -> String {
        let daysAgo = today.dayNumber - fact.sourceDay.dayNumber
        switch fact.type {
        case .bestDay:
            return deck.next(from: bestDayCallbackPool, key: "cb-bestday")
                .replacingOccurrences(of: "{when}", with: coarseWhen(daysAgo: daysAgo))
                .replacingOccurrences(of: "{count}", with: LetterCopy.numberWord(fact.count))
                .replacingOccurrences(
                    of: "{scale}",
                    with: fact.tied ? "one of your biggest days" : "your biggest day"
                )
        case .recovery:
            return deck.next(from: recoveryCallbackPool, key: "cb-recovery")
        case .streakEra:
            let pool = fact.eraDated ? streakEraDatedPool : streakEraCountPool
            return deck.next(from: pool, key: fact.eraDated ? "cb-streak-era" : "cb-streak")
                .replacingOccurrences(of: "{count}", with: LetterCopy.numberWord(fact.streakCount))
                .replacingOccurrences(of: "{when}", with: coarseWhen(daysAgo: daysAgo))
        case .dateEcho:
            return deck.next(from: dateEchoCallbackPool, key: "cb-echo")
                .replacingOccurrences(of: "{monthsago}", with: monthsAgo(fact.monthsBack))
                .replacingOccurrences(of: "{count}", with: LetterCopy.numberWord(fact.count))
        }
    }

    static func bannerText(
        for milestone: AnniversaryMilestone,
        petName: String,
        deck: inout CopyDeck
    ) -> String {
        let template = deck.next(from: anniversaryBannerPool, key: "ann-banner")
        return PetCopyTemplate.render(
            template.replacingOccurrences(of: "{span}", with: span(for: milestone.tier)),
            petName: petName
        )
    }
}
