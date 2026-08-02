//
//  NetworkCallMeter.swift
//  MochiBuddy
//
//  A day-scoped tally of every Firestore call the app makes - the "what
//  does a normal day cost?" number the caching work is judged against.
//  Counted at the same choke points FirestoreReadLog already logs (every
//  server read) plus a recordWrite twin at every write site. Cache hits
//  are deliberately NOT counted - the meter measures the network, and the
//  gap between it and the log's cache-hit lines IS the caching win.
//
//  The reset is lazy: counts are keyed to the local civil day, so the
//  first call after midnight starts from zero with no timer to leak.
//  Batches and transactions count as one call each (round trips, not
//  billed documents). SDK-internal traffic (Auth token refreshes,
//  RevenueCat, Remote Config) is out of reach and out of scope.
//

import Foundation

final class NetworkCallMeter: @unchecked Sendable {

    enum Kind {
        case read
        case write
    }

    struct Snapshot: Equatable {
        var day: String
        var reads: Int
        var writes: Int
        var total: Int { reads + writes }
    }

    static let shared = NetworkCallMeter()

    private enum Key {
        static let day = "mochi.netmeter.day"
        static let reads = "mochi.netmeter.reads"
        static let writes = "mochi.netmeter.writes"
    }

    private let defaults: UserDefaults
    private let today: () -> String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        today: @escaping () -> String = { CivilDay(of: .now, in: .current).dateString }
    ) {
        self.defaults = defaults
        self.today = today
    }

    /// `by` is billed documents for reads (queries pass their result
    /// count; a meter day is then directly comparable to the Firebase
    /// console's read graph). Writes stay 1 per round trip.
    func count(_ kind: Kind, by amount: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        rollOverIfNeeded()
        let key = kind == .read ? Key.reads : Key.writes
        defaults.set(defaults.integer(forKey: key) + amount, forKey: key)
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        rollOverIfNeeded()
        return Snapshot(
            day: defaults.string(forKey: Key.day) ?? today(),
            reads: defaults.integer(forKey: Key.reads),
            writes: defaults.integer(forKey: Key.writes)
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(today(), forKey: Key.day)
        defaults.set(0, forKey: Key.reads)
        defaults.set(0, forKey: Key.writes)
    }

    /// Must be called under the lock: a stored day other than today zeroes
    /// the counters - the midnight reset, paid lazily on the next call.
    private func rollOverIfNeeded() {
        let day = today()
        guard defaults.string(forKey: Key.day) != day else { return }
        defaults.set(day, forKey: Key.day)
        defaults.set(0, forKey: Key.reads)
        defaults.set(0, forKey: Key.writes)
    }
}
