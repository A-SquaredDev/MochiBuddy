//
//  MemoriesCopyTests.swift
//  MochiBuddyTests
//
//  The recovery family's structural restrictions (the rough-letter
//  mechanism, applied): the restriction lives in what the templates CAN
//  say, so a future line can't quietly break the register. Plus slot
//  rendering: no unresolved placeholders ever reach a notification.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct MemoriesCopyTests {

    // MARK: - The recovery family is structurally restricted

    @Test func recoveryPoolsCarryNoCountsComparisonsOrAsks() {
        // Constructions the register bans outright. "again" is checked
        // separately - it may attach to resilience only.
        let banned = [
            "back to", "used to", "back when",
            "more than", "bigger than", "worse than", "fewer than", "less than",
        ]
        for pool in MemoriesCopy.restrictedPools {
            #expect(!pool.isEmpty)
            for template in pool {
                // {name} is the ONLY slot.
                let withoutName = template.replacingOccurrences(of: "{name}", with: "")
                #expect(!withoutName.contains("{"), "unexpected slot in: \(template)")
                // No digits: the family has no count slots and no
                // literals that smuggle one in.
                #expect(!template.contains { $0.isNumber }, "digit in: \(template)")
                // No asks.
                #expect(!template.contains("?"), "ask in: \(template)")
                let lowered = template.lowercased()
                for phrase in banned {
                    #expect(!lowered.contains(phrase), "banned '\(phrase)' in: \(template)")
                }
                // No reference to the user's present pile: nothing in
                // the present tense about what is due or waiting now.
                #expect(!lowered.contains("your list"), "present-pile reference in: \(template)")
                #expect(!lowered.contains("right now"), "present-pile reference in: \(template)")
            }
        }
    }

    @Test func dateEchoNeverClaimsTheWholeList() {
        for template in MemoriesCopy.dateEchoCallbackPool {
            #expect(!template.lowercased().contains("whole list"))
            #expect(!template.lowercased().contains("everything"))
        }
    }

    // MARK: - Slot rendering

    private func day(_ string: String) -> CivilDay { CivilDay(string)! }

    /// Rendering any line and substituting the name must leave no
    /// unresolved placeholder behind.
    private func expectFullyRendered(_ text: String) {
        let rendered = PetCopyTemplate.render(text, petName: "Nori")
        #expect(!rendered.contains("{"), "unresolved slot in: \(rendered)")
        #expect(rendered.contains("Nori") || !text.contains("{name}"))
    }

    @Test func anniversaryAndDeferredTemplatesRenderEverySlot() {
        var deck = CopyDeck()
        for tier in [AnniversaryTier.week, .month, .year(1), .year(2)] {
            let milestone = AnniversaryMilestone(tier: tier, day: day("2026-07-08"))
            for _ in 0..<MemoriesCopy.anniversaryRundownPool.count {
                let opener = MemoriesCopy.rundownOpenerTemplate(
                    for: .anniversary(milestone), today: day("2026-07-08"), deck: &deck
                )
                expectFullyRendered(opener ?? "{missing}")
            }
            for _ in 0..<MemoriesCopy.deferredAnniversaryPool.count {
                let ack = MemoriesCopy.rundownOpenerTemplate(
                    for: .deferredAnniversary(milestone), today: day("2026-07-08"), deck: &deck
                )
                expectFullyRendered(ack ?? "{missing}")
            }
            for _ in 0..<MemoriesCopy.anniversaryBannerPool.count {
                expectFullyRendered(MemoriesCopy.bannerText(
                    for: milestone, petName: "{name}", deck: &deck
                ))
            }
        }
    }

    @Test func callbackTemplatesRenderEverySlot() {
        var deck = CopyDeck()
        let facts = [
            CallbackFact(
                type: .bestDay, factId: "completion-day-2026-06-15",
                sourceDay: day("2026-06-15"), count: 7, tied: true
            ),
            CallbackFact(
                type: .bestDay, factId: "completion-day-2026-06-16",
                sourceDay: day("2026-06-16"), count: 5, tied: false
            ),
            CallbackFact(type: .recovery, factId: "recovery-x", sourceDay: day("2026-06-15")),
            CallbackFact(
                type: .streakEra, factId: "streak-record-23-legacy",
                sourceDay: day("2026-07-08"), streakCount: 23, eraDated: false
            ),
            CallbackFact(
                type: .streakEra, factId: "streak-record-23-2026-06-01",
                sourceDay: day("2026-06-01"), streakCount: 23, eraDated: true
            ),
            CallbackFact(
                type: .dateEcho, factId: "completion-day-2026-06-08",
                sourceDay: day("2026-06-08"), count: 7, monthsBack: 1
            ),
            CallbackFact(
                type: .dateEcho, factId: "completion-day-2026-05-08",
                sourceDay: day("2026-05-08"), count: 6, monthsBack: 2
            ),
        ]
        for fact in facts {
            for _ in 0..<6 {
                expectFullyRendered(MemoriesCopy.callbackLineTemplate(
                    for: fact, today: day("2026-07-08"), deck: &deck
                ))
            }
        }
    }

    @Test func tieAwareScaleNeverFalselySuperlative() {
        var deck = CopyDeck()
        // Walk the pool until the {scale} line surfaces for a TIED fact.
        let tied = CallbackFact(
            type: .bestDay, factId: "completion-day-2026-06-15",
            sourceDay: day("2026-06-15"), count: 7, tied: true
        )
        var sawScaleLine = false
        for _ in 0..<MemoriesCopy.bestDayCallbackPool.count {
            let line = MemoriesCopy.callbackLineTemplate(
                for: tied, today: day("2026-07-08"), deck: &deck
            )
            if line.contains("one of your biggest days") { sawScaleLine = true }
            #expect(!line.contains("your biggest day") || line.contains("one of your biggest days"))
        }
        #expect(sawScaleLine)
    }

    @Test func coarseWhenBucketsAreCoarse() {
        #expect(MemoriesCopy.coarseWhen(daysAgo: 8) == "about a week ago")
        #expect(MemoriesCopy.coarseWhen(daysAgo: 15) == "a couple of weeks ago")
        #expect(MemoriesCopy.coarseWhen(daysAgo: 30) == "about a month ago")
        #expect(MemoriesCopy.coarseWhen(daysAgo: 60) == "a couple of months ago")
        #expect(MemoriesCopy.coarseWhen(daysAgo: 120) == "a while back")
    }

    @Test func spansAndMarks() {
        #expect(MemoriesCopy.span(for: .week) == "One week")
        #expect(MemoriesCopy.span(for: .month) == "One month")
        #expect(MemoriesCopy.span(for: .year(1)) == "One year")
        #expect(MemoriesCopy.span(for: .year(2)) == "Two years")
        #expect(MemoriesCopy.mark(for: .month) == "one-month")
        #expect(MemoriesCopy.mark(for: .year(1)) == "one-year")
        #expect(MemoriesCopy.monthsAgo(1) == "A month")
        #expect(MemoriesCopy.monthsAgo(3) == "Three months")
    }

    @Test func noEmDashesAnywhereInThePools() {
        let pools = [
            MemoriesCopy.anniversaryRundownPool,
            MemoriesCopy.deferredAnniversaryPool,
            MemoriesCopy.anniversaryBannerPool,
            MemoriesCopy.bestDayCallbackPool,
            MemoriesCopy.recoveryCallbackPool,
            MemoriesCopy.streakEraCountPool,
            MemoriesCopy.streakEraDatedPool,
            MemoriesCopy.dateEchoCallbackPool,
        ]
        for pool in pools {
            for template in pool {
                #expect(!template.contains("\u{2014}"), "em dash in: \(template)")
            }
        }
    }
}
