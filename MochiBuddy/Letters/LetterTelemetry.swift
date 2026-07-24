//
//  LetterTelemetry.swift
//  MochiBuddy
//
//  Diagnostic-grade letter instrumentation (Personal Layer, Feature 3):
//  a raw rough-vs-great open-rate comparison confounds tone quality with
//  mood-correlated usage, so events carry the denominators an honest
//  evaluation needs. Never letter text, task names, or observation
//  payloads. os_log now; Firebase Analytics drops in behind the protocol.
//

import Foundation
import os

enum LetterOpenSource: String {
    case notification
    case home
    case archive
}

enum LetterTelemetryEvent {
    case composed(classification: LetterClassification, beatTypes: [LetterBeatType], wordBucket: String)
    /// The Home-envelope impression - the denominator an open-rate needs.
    case indicatorShown
    case opened(
        source: LetterOpenSource,
        classification: LetterClassification,
        timeToOpenBucket: String,
        hasOpenedBefore: Bool
    )
    case shared(variant: String)
}

protocol LetterTelemetry: AnyObject {
    func log(_ event: LetterTelemetryEvent)
}

final class OSLogLetterTelemetry: LetterTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "letters")

    func log(_ event: LetterTelemetryEvent) {
        switch event {
        case .composed(let classification, let beatTypes, let wordBucket):
            logger.info("letter_composed class=\(classification.rawValue, privacy: .public) beats=\(beatTypes.map(\.rawValue).joined(separator: ","), privacy: .public) words=\(wordBucket, privacy: .public)")
        case .indicatorShown:
            logger.info("letter_indicator_shown")
        case .opened(let source, let classification, let bucket, let before):
            logger.info("letter_opened source=\(source.rawValue, privacy: .public) class=\(classification.rawValue, privacy: .public) timeToOpen=\(bucket, privacy: .public) openedBefore=\(before)")
        case .shared(let variant):
            logger.info("letter_shared variant=\(variant, privacy: .public)")
        }
    }
}

enum LetterTelemetryBuckets {

    static func words(_ count: Int) -> String {
        switch count {
        case ..<40: "under-40"
        case ..<70: "40-69"
        case ..<100: "70-99"
        case ...120: "100-120"
        default: "over-120"
        }
    }

    static func timeToOpen(composedAt: Date, openedAt: Date) -> String {
        let hours = openedAt.timeIntervalSince(composedAt) / 3600
        return switch hours {
        case ..<1: "under-1h"
        case ..<12: "1-12h"
        case ..<48: "12-48h"
        case ..<168: "2-7d"
        default: "over-7d"
        }
    }
}
