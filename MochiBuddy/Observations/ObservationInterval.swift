//
//  ObservationInterval.swift
//  MochiBuddy
//
//  The synced append-only log of vacation and lapse intervals (Personal
//  Layer, Feature 4). Momentum eligibility needs to know which HISTORICAL
//  days were vacation or lapsed; nothing else persists that. Synced on
//  users/{uid} because deterministic hysteresis requires every device to
//  fold over identical inputs.
//
//  Honest-fallback rule: `logSince` marks when this profile's log began;
//  for any period predating it, eligibility is unknown and momentum stays
//  silent - no claimed normalization without a data source.
//

import Foundation

struct ObservationInterval: Equatable {

    enum Kind: String {
        case vacation
        case lapse
    }

    let kind: Kind
    let start: Date
    /// Nil while the interval is still open (vacation ongoing, still lapsed).
    var end: Date?

    func contains(_ instant: Date) -> Bool {
        instant >= start && (end.map { instant < $0 } ?? true)
    }
}

extension Array where Element == ObservationInterval {

    /// The open interval of a kind, if any (append/close discipline keeps
    /// at most one open per kind; a malformed log yields the latest).
    func openInterval(_ kind: ObservationInterval.Kind) -> ObservationInterval? {
        last { $0.kind == kind && $0.end == nil }
    }

    /// Log semantics are append-and-close only - entries never disappear.
    func appending(open kind: ObservationInterval.Kind, at start: Date) -> [ObservationInterval] {
        guard openInterval(kind) == nil else { return self }
        return self + [ObservationInterval(kind: kind, start: start, end: nil)]
    }

    func closing(_ kind: ObservationInterval.Kind, at end: Date) -> [ObservationInterval] {
        guard let index = lastIndex(where: { $0.kind == kind && $0.end == nil }) else {
            return self
        }
        var updated = self
        // A close instant before the open start (clock skew, a same-instant
        // toggle) degrades to a zero-length interval, never a negative one.
        updated[index].end = Swift.max(end, updated[index].start)
        return updated
    }
}
