//
//  NetworkCallMeterTests.swift
//  MochiBuddyTests
//
//  The day-scoped Firestore call tally: reads and writes count separately,
//  the midnight reset is structural (day-keyed, no timer), counts persist
//  across instances sharing a defaults store, and Zero starts today over.
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

    @Test("the log choke points feed the shared meter - a read and a write each land once")
    func chokePointsFeedTheMeter() {
        let before = NetworkCallMeter.shared.snapshot()
        FirestoreReadLog.record(NetworkCallMeterTests.self)
        FirestoreReadLog.recordWrite(NetworkCallMeterTests.self)
        FirestoreReadLog.recordCacheHit(NetworkCallMeterTests.self)

        let after = NetworkCallMeter.shared.snapshot()
        // Same-day guard: if this test happens to straddle midnight the
        // deltas can't be asserted; skip rather than flake once a year.
        if before.day == after.day {
            #expect(after.reads == before.reads + 1)
            #expect(after.writes == before.writes + 1, "cache hits must NOT count")
        }
    }
}
