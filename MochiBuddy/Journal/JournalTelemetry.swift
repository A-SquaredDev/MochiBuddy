//
//  JournalTelemetry.swift
//  MochiBuddy
//
//  journal_opened + section impressions (Feature 6). No payloads - the
//  composing features already report their own creation events, and the
//  anti-churn read over journal_opened is correlation, never proof.
//

import Foundation
import os

enum JournalOpenSource: String {
    case tab
    case envelope
    case notification
}

enum JournalTelemetryEvent {
    case opened(source: JournalOpenSource)
    /// Viewport-defined (roughly half the section visible), logged once
    /// per Journal session - lazy or prefetched content never counts.
    case sectionImpression(JournalSection)
}

protocol JournalTelemetry: AnyObject {
    func log(_ event: JournalTelemetryEvent)
}

final class OSLogJournalTelemetry: JournalTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "journal")

    func log(_ event: JournalTelemetryEvent) {
        switch event {
        case .opened(let source):
            logger.info("journal_opened source=\(source.rawValue)")
        case .sectionImpression(let section):
            logger.info("journal_section_impression section=\(section.rawValue)")
        }
    }
}
