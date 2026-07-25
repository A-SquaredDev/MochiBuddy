//
//  SuggestionLedgerTests.swift
//  MochiBuddyTests
//
//  The Feature 5 dismissal ledger: trigger-keyed isolation, the
//  displayed-minute record a re-arm compares against, acceptance
//  round-trips for retention, the per-UID namespace, the schema version
//  gate, and the deletion clear.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
struct SuggestionLedgerTests {

    private func freshDefaults() -> UserDefaults {
        let name = "suggestion-ledger-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func dismissalRoundTripsTheDisplayedMinute() {
        let ledger = SuggestionLedger(defaults: freshDefaults())
        #expect(ledger.dismissedMinute(.newTime, id: "task1", userId: "u1") == nil)

        ledger.recordDismissed(.newTime, id: "task1", displayedMinute: 600, userId: "u1")
        #expect(ledger.dismissedMinute(.newTime, id: "task1", userId: "u1") == 600)
        // A later dismissal of a moved proposal replaces the record.
        ledger.recordDismissed(.newTime, id: "task1", displayedMinute: 720, userId: "u1")
        #expect(ledger.dismissedMinute(.newTime, id: "task1", userId: "u1") == 720)
    }

    @Test func dismissalsAreTriggerKeyed() {
        let ledger = SuggestionLedger(defaults: freshDefaults())
        ledger.recordDismissed(.newTime, id: "task1", displayedMinute: 600, userId: "u1")
        #expect(ledger.dismissedMinute(.reTime, id: "task1", userId: "u1") == nil,
                "dismissing a new-time chip never suppresses a re-time offer")
        #expect(ledger.dismissedMinute(.newTime, id: "task2", userId: "u1") == nil)
    }

    @Test func stateIsNamespacedPerUser() {
        let ledger = SuggestionLedger(defaults: freshDefaults())
        ledger.recordDismissed(.newTime, id: "task1", displayedMinute: 600, userId: "u1")
        #expect(ledger.dismissedMinute(.newTime, id: "task1", userId: "u2") == nil)
    }

    @Test func preallocatedIdSurvivesConceptually() {
        // The dismissal made against a preallocated id is readable under
        // that same id after the save - the id IS the task's id.
        let ledger = SuggestionLedger(defaults: freshDefaults())
        ledger.recordDismissed(.newTime, id: "preallocated-42", displayedMinute: 630, userId: "u1")
        #expect(ledger.dismissedMinute(.newTime, id: "preallocated-42", userId: "u1") == 630)
    }

    @Test func acceptancesRoundTripAndReportOnce() {
        let ledger = SuggestionLedger(defaults: freshDefaults())
        let record = SuggestionLedger.AcceptanceRecord(
            trigger: "reTime", tier: "series", taskId: "task1", seriesId: "series1",
            minute: 1200, acceptedOn: "2026-07-08", retentionReported: false
        )
        ledger.recordAcceptance(record, userId: "u1")

        let byTask = ledger.pendingAcceptances(taskId: "task1", seriesId: nil, userId: "u1")
        #expect(byTask == [record])
        let bySeries = ledger.pendingAcceptances(taskId: "other", seriesId: "series1", userId: "u1")
        #expect(bySeries == [record], "a series occurrence spawn still finds the acceptance")

        ledger.markRetentionReported(record, userId: "u1")
        #expect(ledger.pendingAcceptances(taskId: "task1", seriesId: nil, userId: "u1").isEmpty)
    }

    @Test func acceptanceLogStaysCapped() {
        let ledger = SuggestionLedger(defaults: freshDefaults())
        for index in 0..<25 {
            ledger.recordAcceptance(SuggestionLedger.AcceptanceRecord(
                trigger: "newTime", tier: "global", taskId: "t\(index)", seriesId: nil,
                minute: 600, acceptedOn: "2026-07-08", retentionReported: false
            ), userId: "u1")
        }
        #expect(ledger.state(userId: "u1").acceptances.count == 20)
        #expect(ledger.state(userId: "u1").acceptances.first?.taskId == "t5", "oldest dropped")
    }

    @Test func schemaVersionMismatchClearsWholesale() {
        let defaults = freshDefaults()
        let ledger = SuggestionLedger(defaults: defaults)
        ledger.recordDismissed(.newTime, id: "task1", displayedMinute: 600, userId: "u1")

        var stale = ledger.state(userId: "u1")
        stale.schemaVersion = SuggestionConstants.schemaVersion + 1
        defaults.set(try? JSONEncoder().encode(stale), forKey: "mochi.suggestions.ledger.u1")
        #expect(ledger.state(userId: "u1") == SuggestionLedger.State(),
                "what a dismissal MEANS may have changed - start fresh")
    }

    @Test func deletionClearsTheUserOutright() {
        let ledger = SuggestionLedger(defaults: freshDefaults())
        ledger.recordDismissed(.reTime, id: "series1", displayedMinute: 1200, userId: "u1")
        ledger.clear(userId: "u1")
        #expect(ledger.state(userId: "u1") == SuggestionLedger.State())
    }
}
