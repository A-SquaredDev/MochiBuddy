//
//  NetworkCallMeterTests.swift
//  MochiBuddyTests
//
//  The day-and-account-scoped Firestore call tally: reads and writes count
//  separately, the midnight and account-switch resets are structural
//  (day+uid keyed, no timer or auth listener), counts persist across
//  instances sharing a defaults store, and Zero starts today over.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("NetworkCallMeter")
struct NetworkCallMeterTests {

    private func makeMeter(day: @escaping () -> String) -> (NetworkCallMeter, UserDefaults) {
        let defaults = UserDefaults(suiteName: "netmeter-\(UUID())")!
        return (NetworkCallMeter(defaults: defaults, today: day), defaults)
    }

    @Test("reads and writes tally separately and sum in the total")
    func countsSplit() {
        let (meter, _) = makeMeter { "2026-07-08" }
        meter.count(.read)
        meter.count(.read)
        meter.count(.write)

        let snapshot = meter.snapshot()
        #expect(snapshot.reads == 2)
        #expect(snapshot.writes == 1)
        #expect(snapshot.total == 3)
        #expect(snapshot.day == "2026-07-08")
    }

    @Test("the first call after midnight starts from zero - no timer involved")
    func midnightRollover() {
        var day = "2026-07-08"
        let (meter, _) = makeMeter { day }
        meter.count(.read)
        meter.count(.write)
        #expect(meter.snapshot().total == 2)

        day = "2026-07-09"
        meter.count(.read)
        let snapshot = meter.snapshot()
        #expect(snapshot.reads == 1)
        #expect(snapshot.writes == 0)
        #expect(snapshot.day == "2026-07-09", "yesterday's tally never bleeds into today")
    }

    @Test("a snapshot alone also rolls the day over - the display never shows stale counts")
    func snapshotRollsOver() {
        var day = "2026-07-08"
        let (meter, _) = makeMeter { day }
        meter.count(.read)

        day = "2026-07-09"
        let snapshot = meter.snapshot()
        #expect(snapshot.total == 0)
        #expect(snapshot.day == "2026-07-09")
    }

    @Test("an account switch starts the tally over - the numbers describe the signed-in account only")
    func accountSwitchRollsOver() {
        var uid: String? = "user-a"
        let defaults = UserDefaults(suiteName: "netmeter-\(UUID())")!
        let meter = NetworkCallMeter(defaults: defaults, today: { "2026-07-08" }, uid: { uid })
        meter.count(.read)
        meter.count(.write)
        #expect(meter.snapshot().total == 2)

        uid = "user-b"
        meter.count(.read)
        let snapshot = meter.snapshot()
        #expect(snapshot.reads == 1)
        #expect(snapshot.writes == 0, "user-a's traffic never bleeds into user-b's tally")

        // Signing out is its own identity: the tally must not keep
        // charging user-b for calls made after the session ended.
        uid = nil
        #expect(meter.snapshot().total == 0)
    }

    @Test("counts persist across meter instances sharing a store")
    func persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "netmeter-shared-\(UUID())")!
        let first = NetworkCallMeter(defaults: defaults, today: { "2026-07-08" })
        first.count(.read)
        first.count(.write)

        let second = NetworkCallMeter(defaults: defaults, today: { "2026-07-08" })
        #expect(second.snapshot().total == 2, "the tally survives relaunch, like the day it measures")
    }

    @Test("reset zeroes today without waiting for midnight")
    func resetZeroes() {
        let (meter, _) = makeMeter { "2026-07-08" }
        meter.count(.read)
        meter.reset()
        #expect(meter.snapshot().total == 0)

        meter.count(.write)
        #expect(meter.snapshot().writes == 1, "counting resumes normally after a reset")
    }

    @Test("reads tally billed documents, not round trips")
    func readsCountBilledDocuments() {
        let (meter, _) = makeMeter { "2026-07-08" }
        meter.count(.read, by: 25)
        meter.count(.read)

        let snapshot = meter.snapshot()
        #expect(snapshot.reads == 26,
                "a query returning 25 docs bills 25 reads - the console's number, not the round-trip count")
    }

    @Test("the log choke points feed the shared meter - a read and a write each land once")
    func chokePointsFeedTheMeter() {
        let before = NetworkCallMeter.shared.snapshot()
        FirestoreReadLog.record(NetworkCallMeterTests.self)
        FirestoreReadLog.record(NetworkCallMeterTests.self, docs: 40)
        FirestoreReadLog.record(NetworkCallMeterTests.self, docs: 0)
        FirestoreReadLog.recordWrite(NetworkCallMeterTests.self)
        FirestoreReadLog.recordCacheHit(NetworkCallMeterTests.self)

        let after = NetworkCallMeter.shared.snapshot()
        // Same-day guard: if this test happens to straddle midnight the
        // deltas can't be asserted; skip rather than flake once a year.
        if before.day == after.day {
            #expect(after.reads == before.reads + 42,
                    "1 default + 40 query docs + 1 for the zero-result query (still billed)")
            #expect(after.writes == before.writes + 1, "cache hits must NOT count")
        }
    }
}
