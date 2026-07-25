//
//  PersonalLayerPlanner.swift
//  MochiBuddy
//
//  THE canonical rundown priority, one source of truth (Personal Layer,
//  Feature 2, refining Feature 4):
//
//      streak milestone > anniversary > "crushed yesterday" > callback
//      > observation
//
//  One Personal-Layer line per rundown, ever. The same list applied to
//  the banner lives in MemoriesService (streak owns the day there too).
//
//  A streak-claimed date renders NO rundown line at all: streak
//  celebrations are in-app only (v0.6.1 locked), so the claim suppresses
//  the anniversary and everything below it without inventing a
//  notification-borne streak surface. The letter may still carry both.
//
//  Pure: the whole assignment is a function of (facts, register, ledger
//  cadence state, dates). Two evaluations on the same device agree;
//  cross-device agreement holds for everything except the device-local
//  cadence inputs, per the stated limitation.
//

import Foundation

/// The one Personal-Layer line a rundown may carry.
enum PersonalLayerLine: Equatable {
    /// The existing title override, now priority-governed.
    case crushedYesterday
    /// "One month with Nori today" - leads the day's priorities.
    case anniversary(AnniversaryMilestone)
    /// "While you were away, you and Nori passed the one-month mark" -
    /// the first post-re-entry rundown only.
    case deferredAnniversary(AnniversaryMilestone)
    case callback(CallbackFact)
    case observation(QualifiedObservation)

    /// The identity string the ledger stores per rundown date.
    var ledgerValue: String {
        switch self {
        case .crushedYesterday: "crushed"
        case .anniversary(let milestone): "anniversary:\(milestone.id)"
        case .deferredAnniversary(let milestone): "deferred:\(milestone.id)"
        case .callback(let fact): fact.factId
        case .observation(let observation):
            "obs:\(ObservationLedger.conclusionKey(observation.conclusion))"
        }
    }
}

enum PersonalLayerPlanner {

    /// One rundown morning as the planner sees it - primitives resolved
    /// by the caller at each rundown's own fire time (RundownRanker
    /// precedent).
    struct DayContext {
        let day: CivilDay
        let fireAt: Date
        let register: RundownEmotionalRegister
        let crushedYesterday: Bool
        /// The post-vacation acknowledgment candidate for THIS wake, when
        /// it is the first rundown after re-entry (derived from the
        /// interval log, no stored state).
        let deferredAcknowledgment: AnniversaryMilestone?
        /// Streak claim: a milestone is eligible on this local date -
        /// either reachable by completing today, or already reached.
        let streakClaimed: Bool
    }

    struct Assignment: Equatable {
        let day: CivilDay
        let line: PersonalLayerLine
        /// The register the day was gated under, for callback_shown.
        let register: RundownEmotionalRegister
    }

    /// Whether a streak milestone is eligible on a local date - the
    /// same-date collision test. Depending on StreakTracker's
    /// first-active-day semantics, day-7 and week-1 may land same-date
    /// or adjacent; this never assumes either.
    static func streakClaims(
        day: CivilDay,
        streakCount: Int,
        lastActiveDay: CivilDay?
    ) -> Bool {
        guard let lastActiveDay else { return false }
        // Already reached today (a completion this morning before the
        // evaluation - impossible at wake, real on re-lays).
        if lastActiveDay == day, StreakMilestones.isMilestone(streakCount) { return true }
        // Reachable by completing today: the continuing streak's next
        // count is a milestone.
        if lastActiveDay == day.advanced(by: -1), StreakMilestones.isMilestone(streakCount + 1) {
            return true
        }
        return false
    }

    /// Assign at most one Personal-Layer line to each rundown morning,
    /// in date order, threading callback cadence through the horizon so
    /// pre-laid future rundowns respect the caps among themselves.
    ///
    /// `canSurfaceObservation` wraps ObservationLedger's own gates (weekly
    /// cap, same-week letter/rundown dedup, cooldowns); the planner adds
    /// the priority and one-line rules on top.
    static func assign(
        days: [DayContext],
        miner: CallbackMinerInputs,
        observations: [QualifiedObservation],
        ledger: CallbackLedger.State,
        canSurfaceObservation: (QualifiedObservation, CivilDay) -> Bool
    ) -> [Assignment] {
        var assignments: [Assignment] = []
        // Cadence simulation: consumed ids and callback days grow as the
        // horizon is walked, so day N+2 sees day N's assignment.
        var simulated = ledger
        var observationWeeks: Set<String> = []

        for context in days.sorted(by: { $0.day < $1.day }) {
            guard let line = assignLine(
                context: context,
                miner: miner,
                observations: observations,
                ledger: simulated,
                observationAlreadyThisWeek: observationWeeks.contains(context.day.weekKey),
                canSurfaceObservation: canSurfaceObservation
            ) else { continue }

            assignments.append(Assignment(day: context.day, line: line, register: context.register))
            simulated.scheduled[context.day.dateString] = line.ledgerValue
            if case .observation = line {
                observationWeeks.insert(context.day.weekKey)
            }
        }
        return assignments
    }

    private static func assignLine(
        context: DayContext,
        miner: CallbackMinerInputs,
        observations: [QualifiedObservation],
        ledger: CallbackLedger.State,
        observationAlreadyThisWeek: Bool,
        canSurfaceObservation: (QualifiedObservation, CivilDay) -> Bool
    ) -> PersonalLayerLine? {
        // 1. Streak milestone owns the day - and renders in-app, so the
        //    rundown carries nothing. The anniversary is suppressed, never
        //    deferred (announcing a date on the wrong date is a small
        //    lie); the letter already remembers it honestly.
        if context.streakClaimed { return nil }

        // 2. Anniversary - today's date IS the milestone date.
        if let milestone = AnniversaryCalendar.milestone(adoptedOn: miner.adoptedOn, on: context.day) {
            return .anniversary(milestone)
        }

        // 2b. The post-vacation acknowledgment rides the anniversary slot
        //     on the one first rundown after re-entry.
        if let deferred = context.deferredAcknowledgment {
            return .deferredAnniversary(deferred)
        }

        // 3. Crushed yesterday - the existing beat keeps its place.
        if context.crushedYesterday { return .crushedYesterday }

        // 4. Callback - the deterministic selection contract.
        if let fact = selectCallback(context: context, miner: miner, ledger: ledger) {
            return .callback(fact)
        }

        // 5. Observation - lowest tier, Feature 4's rundown consumer.
        if !observationAlreadyThisWeek {
            let eligible = observations.first {
                canSurfaceObservation($0, context.day)
            }
            if let eligible { return .observation(eligible) }
        }
        return nil
    }

    /// The selection contract: type priority (date echo > recovery >
    /// best day > streak era), then within a type never-told beats
    /// told-and-since-changed, then most recent, then stable factId.
    /// Only the winner consumes cadence; a loser stays fully eligible -
    /// except a losing date echo, which expires silently on its date.
    static func selectCallback(
        context: DayContext,
        miner: CallbackMinerInputs,
        ledger: CallbackLedger.State
    ) -> CallbackFact? {
        guard context.register != .closed else { return nil }

        let facts = CallbackFactMiner.facts(miner, on: context.day)
        guard !facts.isEmpty else { return nil }

        // Cadence gates apply to the slot, not per fact.
        guard ledger.callbackCount(inWeekOf: context.day) < CallbackConstants.weeklyCap else {
            return nil
        }
        if let gap = ledger.nearestCallbackGap(to: context.day),
           gap < CallbackConstants.minGapDays {
            return nil
        }

        let candidates = facts
            .filter { context.register.admits($0.type) }
            .filter { !ledger.consumedFactIds.contains($0.factId) }
        guard !candidates.isEmpty else { return nil }

        return candidates.min { a, b in
            if a.type.priority != b.type.priority { return a.type.priority < b.type.priority }
            // Never-told type beats one that told an earlier version.
            let aTold = ledger.toldTypes[a.type.rawValue] != nil
            let bTold = ledger.toldTypes[b.type.rawValue] != nil
            if aTold != bTold { return !aTold }
            if a.sourceDay != b.sourceDay { return a.sourceDay > b.sourceDay }
            return a.factId < b.factId
        }
    }
}
