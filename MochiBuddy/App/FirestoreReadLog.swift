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

    /// Call at every server-read site - `caller` captures the enclosing
    /// method, so a call site is just `FirestoreReadLog.record(Self.self)`.
    static func record(_ type: Any.Type, _ caller: String = #function) {
        logger.info("read \(String(describing: type), privacy: .public).\(caller, privacy: .public)")
        NetworkCallMeter.shared.count(.read)
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
