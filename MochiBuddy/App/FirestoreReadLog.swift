//
//  FirestoreReadLog.swift
//  MochiBuddy
//
//  Instrumentation for the "what needs caching?" question: every Firestore
//  server read logs its call site so the stream shows which fetches run hot.
//  Watch live with:
//    log stream --level info --predicate 'subsystem == "com.aaronmckain.MochiBuddy" AND category == "firestore-reads"'
//

import Foundation
import os

enum FirestoreReadLog {

    private static let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "firestore-reads")

    /// Call at every server-read site, AFTER the snapshot returns, with
    /// the number of documents it carried - Firestore bills per document
    /// returned, not per query, so this is the number the console shows.
    /// A zero-result query still bills one read (`max(1, docs)`), a doc
    /// get or aggregation is the default 1. Failed reads never log here;
    /// they are not billed. `caller` captures the enclosing method, so a
    /// call site is just `FirestoreReadLog.record(Self.self, docs: n)`.
    static func record(_ type: Any.Type, docs: Int = 1, _ caller: String = #function) {
        let billed = max(1, docs)
        logger.info("read \(String(describing: type), privacy: .public).\(caller, privacy: .public) docs=\(billed, privacy: .public)")
        NetworkCallMeter.shared.count(.read, by: billed)
    }

    /// The write twin: call at every write site (a batch or transaction
    /// counts once - the meter tracks round trips, not billed documents).
    static func recordWrite(_ type: Any.Type, _ caller: String = #function) {
        logger.info("write \(String(describing: type), privacy: .public).\(caller, privacy: .public)")
        NetworkCallMeter.shared.count(.write)
    }

    /// A fetch served from an in-memory cache instead of Firestore - logged
    /// so hit rate is visible next to the reads that did go out. Never
    /// counted by the meter: the gap between the meter and these lines is
    /// the caching win.
    static func recordCacheHit(_ type: Any.Type, _ caller: String = #function) {
        logger.info("cache-hit \(String(describing: type), privacy: .public).\(caller, privacy: .public)")
    }
}
