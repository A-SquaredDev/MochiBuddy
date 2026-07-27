//
//  SuggestionCopyTests.swift
//  MochiBuddyTests
//
//  Provenance can't be misstated by construction: the reason line takes
//  the proposal's scope TIER, and these tests pin the tier-to-phrasing
//  mapping plus the copy-style rules (no em dashes, no emoji, no
//  percentages) and re-time's consent accuracy (it changes the DUE TIME,
//  never "the reminder").
//

import Foundation
import Testing
@testable import MochiBuddy

struct SuggestionCopyTests {

    private let locale = Locale(identifier: "en_US")
    /// The narrow no-break space iOS puts before AM/PM.
    private let sp = "\u{202F}"

    private func proposal(
        trigger: SuggestionTrigger = .newTime,
        tier: SuggestionScopeTier,
        listId: String? = nil,
        minute: Int = 600,
        weekday: Int? = nil
    ) -> SuggestionProposal {
        SuggestionProposal(
            trigger: trigger, tier: tier, listId: listId,
            peakMinute: minute, displayedMinute: minute,
            evidenceCount: 20, isRecurring: false, weekday: weekday
        )
    }

    private var allRenderedCopy: [String] {
        let tiers: [(SuggestionScopeTier, String?)] = [
            (.series, nil), (.list, "Personal"), (.list, nil), (.global, nil),
            (.listWeekday, "Personal"), (.listWeekday, nil), (.globalWeekday, nil),
        ]
        var lines: [String] = []
        for (tier, listName) in tiers {
            for trigger in SuggestionTrigger.allCases {
                let p = proposal(trigger: trigger, tier: tier, listId: listName != nil ? "l1" : nil)
                lines.append(SuggestionCopy.chipLabel(p, petName: "Nori", locale: locale))
                lines.append(SuggestionCopy.reason(p, listName: listName, locale: locale))
                lines.append(SuggestionCopy.accessibilityLabel(
                    p, petName: "Nori", listName: listName, locale: locale
                ))
            }
        }
        lines.append(SuggestionCopy.confirmed(minute: 600, locale: locale))
        lines.append(SuggestionCopy.dismissAccessibilityLabel)
        return lines
    }

    @Test("time rendering is a pure function of minute and locale")
    func timeText() {
        #expect(SuggestionCopy.timeText(minute: 600, locale: locale) == "10:00\(sp)AM")
        #expect(SuggestionCopy.timeText(minute: 1200, locale: locale) == "8:00\(sp)PM")
        #expect(SuggestionCopy.timeText(minute: 0, locale: locale) == "12:00\(sp)AM")
        #expect(SuggestionCopy.timeText(minute: 1410, locale: locale) == "11:30\(sp)PM")
    }

    @Test("tier maps to its own phrasing - a global fallback can never overreach")
    func tierMapping() {
        let series = SuggestionCopy.reason(proposal(tier: .series), listName: nil, locale: locale)
        #expect(series == "This one usually happens around 10:00\(sp)AM.")

        let list = SuggestionCopy.reason(
            proposal(tier: .list, listId: "l1"), listName: "Personal", locale: locale
        )
        #expect(list == "Personal things usually get done in the morning.")

        let global = SuggestionCopy.reason(proposal(tier: .global), listName: nil, locale: locale)
        #expect(global == "You usually finish things in the morning.")
        #expect(!global.contains("Personal"))

        // A global proposal handed a list name STILL renders global copy -
        // the tier is the only voice selector.
        let handed = SuggestionCopy.reason(proposal(tier: .global), listName: "Personal", locale: locale)
        #expect(handed == global)
    }

    @Test("weekday tiers name the day with a distinct verb, never the pooled voice (A4)")
    func weekdayTierMapping() {
        let list = SuggestionCopy.reason(
            proposal(tier: .listWeekday, listId: "l1", weekday: 5),
            listName: "Personal", locale: locale
        )
        #expect(list == "On Thursdays, Personal usually gets done in the morning.")

        let listNameGone = SuggestionCopy.reason(
            proposal(tier: .listWeekday, listId: "l1", weekday: 5), listName: nil, locale: locale
        )
        #expect(listNameGone == "On Thursdays you usually wrap up in the morning.")

        let global = SuggestionCopy.reason(
            proposal(tier: .globalWeekday, weekday: 3), listName: nil, locale: locale
        )
        #expect(global == "On Tuesdays you usually wrap up in the morning.")
        #expect(!global.contains("finish things"), "audibly different from the pooled voice")
    }

    @Test("a list whose name is gone narrows to the global claim, never widens")
    func listNameGone() {
        let line = SuggestionCopy.reason(
            proposal(tier: .list, listId: "l1"), listName: nil, locale: locale
        )
        #expect(line == "You usually finish things in the morning.")
    }

    @Test("chip labels: the pet suggests, re-time describes")
    func labels() {
        let newTime = SuggestionCopy.chipLabel(proposal(tier: .global), petName: "Nori", locale: locale)
        #expect(newTime == "Nori suggests 10:00\(sp)AM.")

        let reTime = SuggestionCopy.chipLabel(
            proposal(trigger: .reTime, tier: .series, minute: 1200), petName: "Nori", locale: locale
        )
        #expect(reTime == "This usually gets done around 8:00\(sp)PM.")
        #expect(SuggestionCopy.confirmed(minute: 600, locale: locale) == "10:00\(sp)AM set")
    }

    @Test("re-time consent accuracy: says due time, persists forward, never 'the reminder'")
    func reTimeConsent() {
        let reason = SuggestionCopy.reason(
            proposal(trigger: .reTime, tier: .series), listName: nil, locale: locale
        )
        #expect(reason.contains("due time"))
        for line in allRenderedCopy {
            #expect(!line.lowercased().contains("reminder"), "consent must name the real semantics: \(line)")
        }
    }

    @Test("copy style: no em dashes, no emoji, no percentages, no evidence talk")
    func copyStyle() {
        for line in allRenderedCopy {
            #expect(!line.contains("\u{2014}"), "no em dashes ever: \(line)")
            #expect(!line.contains("%"), "no percentages: \(line)")
            #expect(!line.lowercased().contains("completion"), "no evidence talk: \(line)")
            #expect(line.unicodeScalars.allSatisfy { $0.value < 0x2190 },
                    "no emoji or symbols: \(line)")
        }
    }

    @Test("band phrasing covers all four bands, night included and affirming")
    func bandPhrases() {
        #expect(SuggestionCopy.bandPhrase(.morning) == "in the morning")
        #expect(SuggestionCopy.bandPhrase(.afternoon) == "in the afternoon")
        #expect(SuggestionCopy.bandPhrase(.evening) == "in the evening")
        #expect(SuggestionCopy.bandPhrase(.night) == "at night")
    }
}
