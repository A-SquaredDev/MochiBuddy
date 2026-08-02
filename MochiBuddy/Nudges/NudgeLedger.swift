//
//  NudgeLedger.swift
//  MochiBuddy
//
//  Shown/dismissed/acted bookkeeping for setup nudges. Sibling of
//  SuggestionLedger/ObservationLedger/CallbackLedger: per-UID UserDefaults
//  JSON, own schema version, cleared on account deletion. Device-local by
//  design - a nudge reappearing once on another device is harmless.
//

import Foundation

@MainActor
final class NudgeLedger {

    struct TopicState: Codable, Equatable {
        var shownCount = 0
        var dismissCount = 0
        var lastShownAt: Date?
        var actedAt: Date?
    }

    struct State: Codable, Equatable {
        var schemaVersion = NudgeConstants.schemaVersion
        var topics: [String: TopicState] = [:]
        /// Global one-at-a-time spacing across all topics.
        var lastNudgeShownAt: Date?
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(for userId: String) -> String {
        "mochi.nudges.ledger.\(userId)"
    }

    func state(userId: String) -> State {
        guard let data = defaults.data(forKey: Self.key(for: userId)),
              let stored = try? JSONDecoder().decode(State.self, from: data),
              stored.schemaVersion == NudgeConstants.schemaVersion
        else {
            // A schema mismatch resets wholesale - what a dismissal MEANS
            // may have changed, and the worst case is one extra nudge.
            return State()
        }
        return stored
    }

    private func save(_ state: State, userId: String) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.key(for: userId))
    }

    /// Account deletion clears the UID's history outright.
    func clear(userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    func recordShown(_ topic: NudgeTopic, userId: String, now: Date = .now) {
        var state = state(userId: userId)
        var topicState = state.topics[topic.rawValue] ?? TopicState()
        topicState.shownCount += 1
        topicState.lastShownAt = now
        state.topics[topic.rawValue] = topicState
        state.lastNudgeShownAt = now
        save(state, userId: userId)
    }

    func recordDismissed(_ topic: NudgeTopic, userId: String, now: Date = .now) {
        var state = state(userId: userId)
        var topicState = state.topics[topic.rawValue] ?? TopicState()
        topicState.dismissCount += 1
        state.topics[topic.rawValue] = topicState
        save(state, userId: userId)
    }

    func recordActed(_ topic: NudgeTopic, userId: String, now: Date = .now) {
        var state = state(userId: userId)
        var topicState = state.topics[topic.rawValue] ?? TopicState()
        topicState.actedAt = now
        state.topics[topic.rawValue] = topicState
        save(state, userId: userId)
    }
}
