//
//  CallbackTelemetry.swift
//  MochiBuddy
//
//  Instrumentation for anniversaries and memory callbacks (Personal
//  Layer, Feature 2). callback_evaluated is the denominator (the
//  Feature 4 lesson, applied): type + qualified + coarse register tier
//  + coarse blocked reason, at most once per type per user-day. Without
//  it, "callbacks are scarce" can't be told apart from healthy
//  sparsity, tight floors, or priority starvation.
//
//  NO payloads anywhere - no dates, counts, streak values, or fact
//  identifiers (locked). os_log now; Firebase Analytics drops in behind
//  the same protocol later.
//

import Foundation
import os

enum CallbackTelemetryEvent {
    case anniversaryShown(tier: String, surface: String)
    case callbackShown(type: CallbackType, register: RundownEmotionalRegister)
    case callbackEvaluated(
        type: CallbackType,
        qualified: Bool,
        register: RundownEmotionalRegister,
        blocked: CallbackBlockedReason?
    )
}

protocol CallbackTelemetry: AnyObject {
    func log(_ event: CallbackTelemetryEvent)
}

final class OSLogCallbackTelemetry: CallbackTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "memories")

    func log(_ event: CallbackTelemetryEvent) {
        switch event {
        case .anniversaryShown(let tier, let surface):
            logger.info("anniversary_shown tier=\(tier, privacy: .public) surface=\(surface, privacy: .public)")
        case .callbackShown(let type, let register):
            logger.info("callback_shown type=\(type.rawValue, privacy: .public) register=\(register.rawValue, privacy: .public)")
        case .callbackEvaluated(let type, let qualified, let register, let blocked):
            logger.info("callback_evaluated type=\(type.rawValue, privacy: .public) qualified=\(qualified) register=\(register.rawValue, privacy: .public) blocked=\(blocked?.rawValue ?? "none", privacy: .public)")
        }
    }
}
