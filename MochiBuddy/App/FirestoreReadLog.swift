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
    }

    /// A fetch served from an in-memory cache instead of Firestore - logged
    /// so hit rate is visible next to the reads that did go out.
    static func recordCacheHit(_ type: Any.Type, _ caller: String = #function) {
        logger.info("cache-hit \(String(describing: type), privacy: .public).\(caller, privacy: .public)")
    }
}
