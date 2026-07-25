//
//  SuggestionLedger.swift
//  MochiBuddy
//
//  Dismissals + acceptance records for suggested times (Personal Layer,
//  Feature 5). Cadence state ONLY: proposals are pure functions of synced
//  data, so nothing here can change what would be suggested - only
//  whether the chip shows. Sibling of ObservationLedger/CallbackLedger:
//  per-UID UserDefaults JSON, own schema version, cleared on account
//  deletion. Honest limitation, accepted for v1 (spec-pinned): the
//  ledger is device-local, so a dismissal holds per device; another
//  device may show the same chip, identically worded by determinism.
//

import Foundation

@MainActor
final class SuggestionLedger {

    struct AcceptanceRecord: Codable, Equatable {
        var trigger: String
        var tier: String
        var taskId: String
        var seriesId: String?
        /// The accepted DISPLAYED minute.
        var minute: Int
        /// Civil date of the acceptance.
        var acceptedOn: String
        var retentionReported: Bool
    }

    struct State: Codable, Equatable {
        var schemaVersion: Int = SuggestionConstants.schemaVersion
        /// "{trigger}|{id}" -> rounded displayed minute at dismissal.
        /// id = taskId for new-time (preallocated for unsaved tasks),
        /// seriesId for re-time - trigger-keyed isolation by construction.
        var dismissed: [String: Int] = [:]
        /// Accepted suggestions awaiting the downstream retention check.
        var acceptances: [AcceptanceRecord] = []
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(for userId: String) -> String {
        "mochi.suggestions.ledger.\(userId)"
    }

    static func dismissKey(_ trigger: SuggestionTrigger, id: String) -> String {
        "\(trigger.rawValue)|\(id)"
    }

    // MARK: - State

    func state(userId: String) -> State {
        guard let data = defaults.data(forKey: Self.key(for: userId)),
              let stored = try? JSONDecoder().decode(State.self, from: data),
              stored.schemaVersion == SuggestionConstants.schemaVersion
        else {
            // A schema mismatch clears cadence wholesale - what a
            // dismissal MEANS may have changed. Losing it is never
            // user-visible beyond a chip reappearing once.
            return State()
        }
        return stored
    }

    private func save(_ state: State, userId: String) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.key(for: userId))
    }

    /// Account deletion clears the UID's cadence outright.
    func clear(userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    // MARK: - Dismissals (once-until-changed on the displayed proposal)

    /// The displayed minute stored by the last dismissal of this exact
    /// trigger+id, nil when never dismissed.
    func dismissedMinute(_ trigger: SuggestionTrigger, id: String, userId: String) -> Int? {
        state(userId: userId).dismissed[Self.dismissKey(trigger, id: id)]
    }

    func recordDismissed(
        _ trigger: SuggestionTrigger, id: String, displayedMinute: Int, userId: String
    ) {
        var state = state(userId: userId)
        state.dismissed[Self.dismissKey(trigger, id: id)] = displayedMinute
        save(state, userId: userId)
    }

    // MARK: - Acceptances (retention's input)

    func recordAcceptance(_ record: AcceptanceRecord, userId: String) {
        var state = state(userId: userId)
        state.acceptances.append(record)
        // The log stays tiny - retention reports once, then the record
        // is dead weight.
        state.acceptances = Array(state.acceptances.suffix(20))
        save(state, userId: userId)
    }

    /// Unreported acceptances for a task (or its series) - the retention
    /// check runs when the same target is next edited.
    func pendingAcceptances(taskId: String, seriesId: String?, userId: String) -> [AcceptanceRecord] {
        state(userId: userId).acceptances.filter { record in
            guard !record.retentionReported else { return false }
            if record.taskId == taskId { return true }
            if let seriesId, record.seriesId == seriesId { return true }
            return false
        }
    }

    func markRetentionReported(_ record: AcceptanceRecord, userId: String) {
        var state = state(userId: userId)
        if let index = state.acceptances.firstIndex(of: record) {
            state.acceptances[index].retentionReported = true
            save(state, userId: userId)
        }
    }
}
