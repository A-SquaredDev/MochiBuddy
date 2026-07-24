//
//  LetterComposerTests.swift
//  MochiBuddyTests
//
//  The pure composer (Personal Layer, Feature 3): classification
//  precedence, two-phase beat selection, the rough set's structural
//  restriction, deterministic rotation, and both share variants. All
//  against shipped-default constants, never mutated.
//

import Foundation
import Testing
@testable import MochiBuddy

private func makeSummary(
    periodId: String = "letter-2026-06-29",
    completionCount: Int = 8,
    tasksDueCount: Int = 6,
    overdueDayCount: Int = 0,
    trailingAverage: Double? = 8,
    vacationOverlap: Bool = false,
    bestDay: PeriodSummary.BestDay? = nil,
    milestonesLanded: [Int] = [],
    comeback: PeriodSummary.ComebackFact? = nil,
    observation: ObservationConclusion? = nil,
    listReturnName: String? = nil,
    petName: String = "Nori",
    priorLineIds: [String] = []
) -> PeriodSummary {
    PeriodSummary(
        periodId: periodId,
        petName: petName,
        adoptedOn: "2026-03-01",
        completionCount: completionCount,
        tasksDueCount: tasksDueCount,
        overdueDayCount: overdueDayCount,
        trailingAverage: trailingAverage,
        vacationOverlap: vacationOverlap,
        bestDay: bestDay,
        milestonesLanded: milestonesLanded,
        comeback: comeback,
        observationConclusion: observation,
        listReturnName: listReturnName,
        hadUserForeground: true,
        priorLineIds: priorLineIds
    )
}

@Suite("Letters · classification")
struct LetterClassificationTests {

    @Test("the classification table, boundary values included")
    func table() {
        // Great: >= 1.5x trailing average AND <= 1 overdue day.
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 12, trailingAverage: 8, vacationOverlap: false
        )) == .great, "12 is exactly 1.5x of 8 - boundary inclusive")
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 12, overdueDayCount: 2, trailingAverage: 8
        )) == .steady, "two overdue days disqualify great")

        // Rough by overdue days: >= 4.
        #expect(LetterClassifier.classify(makeSummary(overdueDayCount: 4)) == .rough)
        #expect(LetterClassifier.classify(makeSummary(overdueDayCount: 3)) != .rough)

        // Rough by collapse: < 25% of trailing average WITH tasks due.
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 1, tasksDueCount: 5, trailingAverage: 8
        )) == .rough)
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 2, tasksDueCount: 5, trailingAverage: 8
        )) != .rough, "exactly 25% is not a collapse")

        // Quiet: <= 2 completions and <= 2 dues.
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 2, tasksDueCount: 2, trailingAverage: nil
        )) == .quiet)

        // Steady is the residual.
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 8, trailingAverage: 8
        )) == .steady)
    }

    @Test("precedence: a rough week that ends in a vacation is a vacation-partial letter")
    func precedence() {
        #expect(LetterClassifier.classify(makeSummary(
            overdueDayCount: 6, vacationOverlap: true
        )) == .vacationPartial, "rest was the right call, and the letter treats it that way")
    }

    @Test("no trailing history: neither great nor ratio-rough is reachable")
    func noHistory() {
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 30, tasksDueCount: 10, trailingAverage: nil
        )) == .steady)
        #expect(LetterClassifier.classify(makeSummary(
            completionCount: 1, tasksDueCount: 8, trailingAverage: nil
        )) == .steady)
    }
}

@Suite("Letters · composer")
struct LetterComposerTests {

    @Test("same summary, byte-identical letter - both variants, no hidden state")
    func determinism() {
        let summary = makeSummary(
            bestDay: .init(weekdayName: "Thursday", count: 6),
            milestonesLanded: [30],
            comeback: .init(taskTitle: "Call the dentist", completedWeekdayName: "Tuesday"),
            observation: .weekday(3)
        )
        let first = LetterComposer.compose(summary: summary)
        let second = LetterComposer.compose(summary: summary)
        #expect(first == second)
    }

    @Test("structure: salutation, beats by priority, closing, signature")
    func structure() {
        let summary = makeSummary(
            bestDay: .init(weekdayName: "Thursday", count: 6),
            milestonesLanded: [30]
        )
        let letter = LetterComposer.compose(summary: summary)
        #expect(letter.beatTypes == [.milestone, .bestDay])
        #expect(letter.fullText.hasSuffix("From Nori"))
        #expect(letter.fullText.contains("Thirty".lowercased()) || letter.fullText.contains("thirty"),
                "milestone counts are spelled, not numeral")
        #expect(letter.fullText.contains("Thursday"))
    }

    @Test("beat cap: never more than maxBeats optional beats")
    func beatCap() {
        let summary = makeSummary(
            bestDay: .init(weekdayName: "Thursday", count: 6),
            milestonesLanded: [7],
            comeback: .init(taskTitle: "Taxes", completedWeekdayName: "Friday"),
            observation: .band(.morning),
            listReturnName: "Personal"
        )
        let letter = LetterComposer.compose(summary: summary)
        #expect(letter.beatTypes.count == LetterConstants.maxBeats)
        #expect(letter.beatTypes == [.milestone, .comeback, .bestDay],
                "priority order, insight beats crowded out entirely here")
    }

    @Test("one insight-family beat total: observation XOR list return, never both")
    func insightFamilyCap() {
        let summary = makeSummary(
            observation: .band(.evening),
            listReturnName: "Personal"
        )
        let letter = LetterComposer.compose(summary: summary)
        #expect(letter.beatTypes.contains(.observation))
        #expect(!letter.beatTypes.contains(.listReturn),
                "a letter must not contain two separate 'Mochi analyzed you' moments")
    }

    @Test("a steady week with no notable facts still gets one honest beat")
    func steadyFallback() {
        let letter = LetterComposer.compose(summary: makeSummary())
        #expect(letter.beatTypes == [.smallTruePositive])
        #expect(!letter.fullText.isEmpty)
    }

    @Test("quiet: the single cozy beat, nothing else")
    func quietForm() {
        let letter = LetterComposer.compose(summary: makeSummary(
            completionCount: 1, tasksDueCount: 1, trailingAverage: nil
        ))
        #expect(letter.classification == .quiet)
        #expect(letter.beatTypes == [.quiet])
    }

    @Test("vacation-partial: the vacation beat is structural and first")
    func vacationPartialForm() {
        let letter = LetterComposer.compose(summary: makeSummary(
            vacationOverlap: true,
            milestonesLanded: [7]
        ))
        #expect(letter.classification == .vacationPartial)
        #expect(letter.beatTypes.first == .vacation, "structural beats are never displaced")
        #expect(letter.beatTypes.contains(.milestone))
    }

    // MARK: - The rough contract

    @Test("rough: presence first, max two beats, and the tempting facts stay OUT")
    func roughSelection() {
        let letter = LetterComposer.compose(summary: makeSummary(
            completionCount: 2,
            overdueDayCount: 5,
            bestDay: .init(weekdayName: "Monday", count: 4),
            milestonesLanded: [50],
            comeback: .init(taskTitle: "Form 1099", completedWeekdayName: "Friday"),
            observation: .weekday(3)
        ))
        #expect(letter.classification == .rough)
        #expect(letter.beatTypes.first == .presence)
        #expect(letter.beatTypes.count <= 2)
        #expect(Set(letter.beatTypes).isSubset(of: [.presence, .smallTruePositive]))
        #expect(!letter.fullText.contains("1099"),
                "the restricted template set forbids title interpolation - the numeral backstop can't false-trip")
        let hasDigit = letter.fullText.contains { $0.isNumber }
        #expect(!hasDigit, "the numeral scan backstop")
        #expect(!letter.fullText.contains("?"), "zero ask")
    }

    @Test("rough with zero completions: presence alone - no manufactured positive")
    func roughZeroCompletions() {
        let letter = LetterComposer.compose(summary: makeSummary(
            completionCount: 0, tasksDueCount: 5, overdueDayCount: 5
        ))
        #expect(letter.beatTypes == [.presence])
    }

    @Test("the rough template pools are structurally restricted - the policy, not the backstop")
    func roughPoolsStructure() {
        for pool in LetterCopy.roughRestrictedPools {
            for template in pool {
                for text in [template.full, template.priv] {
                    let withoutName = text.replacingOccurrences(of: "{name}", with: "")
                    #expect(!withoutName.contains("{"),
                            "no interpolation slot but {name}: \(text)")
                    let hasDigit = text.contains { $0.isNumber }
                    #expect(!hasDigit, "no quantities: \(text)")
                    #expect(!text.contains("?"), "no ask: \(text)")
                }
            }
        }
    }

    // MARK: - Variants

    @Test("the private variant replaces task names with neutral phrasing at composition")
    func privateVariant() {
        let letter = LetterComposer.compose(summary: makeSummary(
            comeback: .init(taskTitle: "Call the dentist", completedWeekdayName: "Tuesday")
        ))
        #expect(letter.beatTypes.contains(.comeback))
        #expect(letter.fullText.contains("Call the dentist"))
        #expect(!letter.privateRendersTaskTitle(title: "Call the dentist"))
        #expect(letter.privateText.contains("Tuesday"), "the day survives; the title doesn't")
    }

    @Test("letter length lands in the 40-120 word body budget")
    func wordBudget() {
        let summaries = [
            makeSummary(),
            makeSummary(completionCount: 1, tasksDueCount: 1, trailingAverage: nil),
            makeSummary(completionCount: 0, tasksDueCount: 5, overdueDayCount: 5),
            makeSummary(
                bestDay: .init(weekdayName: "Thursday", count: 6),
                milestonesLanded: [30],
                comeback: .init(taskTitle: "Taxes", completedWeekdayName: "Friday")
            ),
        ]
        for summary in summaries {
            let letter = LetterComposer.compose(summary: summary)
            let words = letter.fullText.split(whereSeparator: \.isWhitespace).count
            #expect((40...125).contains(words),
                    "\(letter.classification): \(words) words")
        }
    }

    // MARK: - Rotation

    @Test("don't-repeat-last-N: a recently used line advances to the next")
    func rotationAvoidsRecent() {
        let fresh = LetterComposer.compose(summary: makeSummary())
        let avoided = LetterComposer.compose(summary: makeSummary(
            priorLineIds: fresh.lineIds
        ))
        #expect(fresh.lineIds != avoided.lineIds,
                "the archive's recent line ids must steer selection away")
        // And the steering itself is deterministic.
        let again = LetterComposer.compose(summary: makeSummary(priorLineIds: fresh.lineIds))
        #expect(avoided == again)
    }

    @Test("different periods naturally rotate lines via the period hash")
    func periodHashVariety() {
        let a = LetterComposer.compose(summary: makeSummary(periodId: "letter-2026-06-29"))
        let b = LetterComposer.compose(summary: makeSummary(periodId: "letter-2026-07-06"))
        // Not guaranteed different for every pool, but the id sets must
        // not be forced equal - sanity that the hash actually varies.
        #expect(a.summaryHash != b.summaryHash)
    }

    @Test("no emoji, no em dashes, anywhere in letter copy")
    func copyStyle() {
        let pools = [
            LetterCopy.standardSalutations, LetterCopy.quietSalutations,
            LetterCopy.roughSalutations, LetterCopy.vacationSalutations,
            LetterCopy.milestonePool, LetterCopy.comebackPool, LetterCopy.bestDayPool,
            LetterCopy.observationWeekdayPool, LetterCopy.observationMorningPool,
            LetterCopy.observationAfternoonPool, LetterCopy.observationEveningPool,
            LetterCopy.observationNightPool, LetterCopy.observationMomentumPool,
            LetterCopy.observationComebackPool, LetterCopy.listReturnPool,
            LetterCopy.presencePool, LetterCopy.smallTruePositivePool,
            LetterCopy.vacationPool, LetterCopy.quietPool,
            LetterCopy.standardClosings, LetterCopy.quietClosings, LetterCopy.roughClosings,
        ]
        for template in pools.joined() {
            for text in [template.full, template.priv] {
                #expect(!text.contains("\u{2014}"), "no em dashes: \(text)")
                let nonAsciiEmoji = text.unicodeScalars.contains {
                    !$0.isASCII && $0.properties.isEmojiPresentation
                }
                #expect(!nonAsciiEmoji, "no emoji in prose: \(text)")
            }
        }
    }
}

private extension LetterComposer.ComposedLetter {
    func privateRendersTaskTitle(title: String) -> Bool {
        privateText.contains(title)
    }
}
