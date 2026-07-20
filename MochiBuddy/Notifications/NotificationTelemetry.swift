//
//  NotificationTelemetry.swift
//  MochiBuddy
//
//  Instrumentation for the escalate-at-the-floor bet (design doc: Winback
//  & instrumentation): every event tagged with the mood state at the
//  time, NEVER a task title. os_log now; Firebase Analytics (roadmap #7)
//  drops in behind the same protocol later.
//

import Foundation
import os

enum NotificationTelemetryEvent {
    /// A re-lay ran: what triggered it, what changed, the band it saw.
    case relaid(trigger: String, scheduled: Int, removed: Int, band: MoodBand)
    /// A notification action was performed (complete, snooze, pet, shh).
    case action(name: String, band: MoodBand?)
    /// The shh valve was pulled - the in-app alternative to the OS switch.
    case shhActivated(band: MoodBand)
}

protocol NotificationTelemetry: AnyObject {
    func log(_ event: NotificationTelemetryEvent)
}

final class OSLogNotificationTelemetry: NotificationTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "notifications")

    func log(_ event: NotificationTelemetryEvent) {
        switch event {
        case .relaid(let trigger, let scheduled, let removed, let band):
            logger.info("relay trigger=\(trigger, privacy: .public) scheduled=\(scheduled) removed=\(removed) band=\(band.rawValue)")
        case .action(let name, let band):
            logger.info("action name=\(name, privacy: .public) band=\(band?.rawValue ?? -1)")
        case .shhActivated(let band):
            logger.info("shh band=\(band.rawValue)")
        }
    }
}
