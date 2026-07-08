//
//  ComfortBufferTests.swift
//  MochiBuddyTests
//
//  The comfort buffer is temporary and capped — pets/treats decay back to
//  the baseline and can never exceed +30 no matter how much is spent.
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("BufferBoost · decay math")
struct BufferBoostTests {

    private let boost = BufferBoost(lift: 20, startedAt: Dates.now, duration: 2 * 3600)

    @Test("a fresh boost is worth its full lift")
    func fresh() {
        #expect(abs(boost.value(at: Dates.now) - 20) < 0.001)
    }

    @Test("a boost decays linearly to zero over its duration")
    func linearDecay() {
        #expect(abs(boost.value(at: Dates.hours(1)) - 10) < 0.001)
        #expect(abs(boost.value(at: Dates.hours(0.5)) - 15) < 0.001)
    }

    @Test("an expired boost is worth exactly zero, never negative")
    func expired() {
        #expect(boost.value(at: Dates.hours(2)) == 0)
        #expect(boost.value(at: Dates.hours(50)) == 0)
    }

    @Test("a boost from the future contributes nothing yet")
    func futureBoost() {
        let future = BufferBoost(lift: 20, startedAt: Dates.hours(5), duration: 3600)
        #expect(future.value(at: Dates.now) == 0)
    }
}

@Suite("ComfortBufferStore")
struct ComfortBufferStoreTests {

    private func makeStore() -> (UserDefaultsComfortBufferStore, UserDefaults, String) {
        let suite = "mochi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (UserDefaultsComfortBufferStore(defaults: defaults), defaults, suite)
    }

    @Test("a pet lifts the buffer by its lift value")
    func petLifts() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.add(lift: TreatCatalog.Pet.lift, duration: TreatCatalog.Pet.duration)
        let value = store.currentValue(now: .now)
        #expect(abs(value - TreatCatalog.Pet.lift) < 0.1)
    }

    @Test("boosts stack, but the total is capped at +30")
    func capped() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        for _ in 0..<5 {
            store.add(lift: 20, duration: 6 * 3600) // 5 cupcakes = 100 raw
        }
        #expect(store.currentValue(now: .now) == MoodEngine.Constants.bufferCap)
    }

    @Test("the buffer drains back toward zero over time")
    func drains() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.add(lift: 20, duration: 2 * 3600)
        let nowish = store.currentValue(now: .now)
        let later = store.currentValue(now: Date.now.addingTimeInterval(3600))
        let expired = store.currentValue(now: Date.now.addingTimeInterval(3 * 3600))
        #expect(later < nowish)
        #expect(abs(later - 10) < 0.1)
        #expect(expired == 0)
    }

    @Test("every treat in the catalog beats the free pet on duration")
    func treatsBeatThePet() {
        for treat in TreatCatalog.all {
            #expect(treat.duration > TreatCatalog.Pet.duration,
                    "\(treat.name) must outlast a free pet or nobody buys it")
            #expect(treat.lift > TreatCatalog.Pet.lift,
                    "\(treat.name) should also lift more than a pet")
        }
    }

    @Test("treat prices scale with duration, not lift (duration is the currency)")
    func pricesScaleWithDuration() {
        let sorted = TreatCatalog.all.sorted { $0.duration < $1.duration }
        let costs = sorted.map(\.cost)
        #expect(costs == costs.sorted(), "longer comfort must never be cheaper")
        // Lift differences stay small — the buffer cap makes lift a bad differentiator.
        let lifts = sorted.map(\.lift)
        #expect((lifts.max()! - lifts.min()!) <= 5)
    }

    @Test("boosts persist across store instances (same defaults)")
    func persistence() {
        let suite = "mochi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        UserDefaultsComfortBufferStore(defaults: defaults).add(lift: 8, duration: 900)
        let reloaded = UserDefaultsComfortBufferStore(defaults: defaults)
        #expect(reloaded.currentValue(now: .now) > 7)
    }
}
