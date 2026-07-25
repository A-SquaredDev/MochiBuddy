//
//  CallbackLedgerTests.swift
//  MochiBuddyTests
//
//  The Feature 2 cadence ledger: fold idempotency (freeze the past,
//  replace the future, un-consume dropped lines), the derived cadence
//  queries, the per-UID namespace, the schema version gate, and the
//  deletion clear.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct CallbackLedgerTests {

    private func day(_ string: String) -> CivilDay { CivilDay(string)! }

    private func freshDefaults() -> UserDefaults {
        let name = "callback-ledger-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Fold

    @Test func foldFreezesPastCallbacksIntoTheToldRecord() {
        var state = CallbackLedger.State()
        state.scheduled = [
            "2026-07-01": "completion-day-2026-06-10",
            "2026-07-03": "anniversary:anniversary-week-2026-07-03",
            "2026-07-10": "recovery-abcd1234",
        ]
        let changed = CallbackLedger.fold(
            assignments: ["2026-07-10": "recovery-abcd1234"],
            today: day("2026-07-08"),
            into: &state
        )
        // The past callback froze; the past anniversary marker just
        // dropped (date-bound, no once-ever state to keep).
        #expect(state.toldFacts["completion-day-2026-06-10"] == "2026-07-01")
        #expect(state.toldFacts.count == 1)
        #expect(state.toldTypes["bestDay"] == "2026-07-01")
        #expect(state.toldTypes["dateEcho"] == "2026-07-01")
        // The unchanged future entry is kept and NOT reported as new.
        #expect(state.scheduled == ["2026-07-10": "recovery-abcd1234"])
        #expect(changed.isEmpty)
    }

    @Test func foldReplacesTheFutureAndUnconsumesDroppedLines() {
        var state = CallbackLedger.State()
        state.scheduled = ["2026-07-10": "recovery-abcd1234"]
        state.rendered = ["2026-07-10": "You've dug out before. {name} never doubted it."]
        // The register changed: the relay now assigns nothing for the
        // 10th - the fact un-consumes (its notification was wiped).
        let changed = CallbackLedger.fold(
            assignments: [:], today: day("2026-07-08"), into: &state
        )
        #expect(changed.isEmpty)
        #expect(state.scheduled.isEmpty)
        #expect(state.rendered.isEmpty)
        #expect(!state.consumedFactIds.contains("recovery-abcd1234"))
    }

    @Test func foldReportsOnlyChangedDatesAndDropsTheirRenderings() {
        var state = CallbackLedger.State()
        state.scheduled = ["2026-07-10": "completion-day-2026-06-10"]
        state.rendered = ["2026-07-10": "old line"]
        let changed = CallbackLedger.fold(
            assignments: [
                "2026-07-10": "completion-day-2026-06-10",   // unchanged
                "2026-07-12": "crushed",                     // new
            ],
            today: day("2026-07-08"),
            into: &state
        )
        #expect(changed == ["2026-07-12": "crushed"])
        // The unchanged date keeps its stored rendering.
        #expect(state.rendered["2026-07-10"] == "old line")
    }

    // MARK: - Derived cadence

    @Test func consumedIncludesFrozenAndScheduled() {
        var state = CallbackLedger.State()
        state.toldFacts["streak-record-23-legacy"] = "2026-06-01"
        state.scheduled = [
            "2026-07-10": "completion-day-2026-06-10",
            "2026-07-12": "obs:weekday:3",       // markers never consume callback cadence
            "2026-07-13": "crushed",
        ]
        #expect(state.consumedFactIds == ["streak-record-23-legacy", "completion-day-2026-06-10"])
        #expect(state.callbackCount(inWeekOf: day("2026-07-10")) == 1)
        #expect(state.nearestCallbackGap(to: day("2026-07-13")) == 3)
    }

    // MARK: - Persistence

    @Test func perUidNamespaceAndClear() {
        let ledger = CallbackLedger(defaults: freshDefaults())
        var state = ledger.state(userId: "userA")
        state.toldFacts["recovery-x"] = "2026-07-01"
        ledger.save(state, userId: "userA")

        #expect(ledger.state(userId: "userA").toldFacts.count == 1)
        #expect(ledger.state(userId: "userB").toldFacts.isEmpty)

        ledger.clear(userId: "userA")
        #expect(ledger.state(userId: "userA").toldFacts.isEmpty)
    }

    @Test func schemaVersionGateWipesStaleState() {
        let defaults = freshDefaults()
        let ledger = CallbackLedger(defaults: defaults)
        var state = ledger.state(userId: "user1")
        state.schemaVersion = CallbackLedger.schemaVersion - 1
        state.toldFacts["recovery-x"] = "2026-07-01"
        ledger.save(state, userId: "user1")
        // A mismatched schema decodes to a fresh slate.
        #expect(ledger.state(userId: "user1") == CallbackLedger.State())
    }
}
