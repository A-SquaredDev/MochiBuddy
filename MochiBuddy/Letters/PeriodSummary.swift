//
//  PeriodSummary.swift
//  MochiBuddy
//
//  The composer's one input (Personal Layer, Feature 3): every fact a
//  letter may draw on, gathered by the composition service from
//  server-backed state behind the online barrier, then handed to the pure
//  composer. Classification is task facts only - no mood-replay
//  dependency - evaluated on the closed period.
//

import Foundation

struct PeriodSummary: Equatable {

    struct BestDay: Equatable {
        let weekdayName: String
        let count: Int
    }

    struct ComebackFact: Equatable {
        /// The cleared task's title - full variant only; the private
        /// variant always uses neutral phrasing composed from beat data.
        let taskTitle: String
        let completedWeekdayName: String
    }

    /// A relationship anniversary that landed inside the period (Personal
    /// Layer, Feature 2 closing Feature 3's noted gap). The letter
    /// REMEMBERS the date - even one a streak milestone owned on the
    /// surfaces, and one that passed during a partial-vacation period
    /// (a fully covered period composes no letter, so "only if a letter
    /// otherwise exists" is structural).
    struct AnniversaryFact: Equatable {
        let tier: AnniversaryTier
        /// The mark's date fell inside a vacation interval - phrasing
        /// acknowledges the pause honestly.
        let duringVacation: Bool
    }

    let periodId: String
    let petName: String
    let adoptedOn: String?

    // Task facts (classification inputs).
    let completionCount: Int
    /// Tasks that came due inside the period (completed or not).
    let tasksDueCount: Int
    /// Period days on which at least one task sat overdue.
    let overdueDayCount: Int
    /// Mean completions across up to 4 trailing periods; nil with no
    /// prior history (a brand-new user can't be "great" or ratio-"rough").
    let trailingAverage: Double?
    /// Vacation covered part of the period (a fully-covered period never
    /// reaches the composer - it composes nothing).
    let vacationOverlap: Bool

    // Beat facts.
    let bestDay: BestDay?
    /// Streak milestones landed inside the period, ascending.
    let milestonesLanded: [Int]
    /// The relationship anniversary landed this period, if any.
    var anniversary: AnniversaryFact? = nil
    let comeback: ComebackFact?
    /// Pre-filtered by the service: the highest-priority qualified
    /// observation not already surfaced this week (Feature 4's dedup).
    let observationConclusion: ObservationConclusion?
    /// Surviving list name for a list-return event that fired this period.
    let listReturnName: String?
    /// The qualified list-return event behind listReturnName - carried so
    /// a told beat can be recorded in the ledger's event log under its
    /// REAL key (listId|firedOn), not a fabricated one.
    var listReturnObservation: QualifiedObservation? = nil

    /// From the create-only activityWeeks marker - the deterministic
    /// dormancy arbiter (gating input; the composer never reads it).
    let hadUserForeground: Bool

    /// Recent archive line ids - powers don't-repeat-last-N rotation.
    let priorLineIds: [String]
}

enum LetterClassifier {

    /// Precedence: vacation-partial > rough > great > quiet > steady.
    /// A rough period that ends in a vacation start is a vacation-partial
    /// letter - rest was the right call, and the letter treats it that way.
    static func classify(_ summary: PeriodSummary) -> LetterClassification {
        if summary.vacationOverlap {
            return .vacationPartial
        }
        if summary.overdueDayCount >= LetterConstants.roughOverdueDays {
            return .rough
        }
        if let average = summary.trailingAverage, average > 0,
           Double(summary.completionCount) < 0.25 * average,
           summary.tasksDueCount > 0 {
            return .rough
        }
        if let average = summary.trailingAverage, average > 0,
           Double(summary.completionCount) >= LetterConstants.greatRatio * average,
           summary.overdueDayCount <= 1 {
            return .great
        }
        if summary.completionCount <= LetterConstants.quietMax, summary.tasksDueCount <= 2 {
            return .quiet
        }
        return .steady
    }
}
