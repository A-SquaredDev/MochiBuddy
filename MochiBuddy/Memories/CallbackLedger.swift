//
//  CallbackLedger.swift
//  MochiBuddy
//
//  Surfacing cadence ONLY (Personal Layer, Feature 2) - a sibling of
//  ObservationLedger with its own namespace and schema version, so an
//  observation algorithm bump can never wipe callback state and vice
//  versa. Nothing here can change a fact; losing the ledger only
//  affects cadence - facts recompute identically.
//
//  Honest limitation, accepted for v1 (spec-pinned): this is
//  device-local, so once-ever and the caps are per-device guarantees.
//  A second device may independently tell the same fact once; the line
//  is identical by determinism, so the duplicate is repetitive rather
//  than confusing. Syncing a compact history is the v2 escape hatch.
//
//  Only a callback that is actually selected and scheduled consumes
//  cadence. Re-lays are idempotent by construction: each relay REPLACES
//  the assignments for today-and-future rundown dates, and past-dated
//  assignments freeze into the told-once record.
//

import Foundation

@MainActor
final class CallbackLedger {

    struct State: Codable, Equatable {
        var schemaVersion: Int = CallbackLedger.schemaVersion
        /// factId -> civil day told (frozen past assignments). The
        /// once-until-changed record - never pruned; it stays tiny
        /// because identities only change when facts materially do.
        var toldFacts: [String: String] = [:]
        /// callback type raw -> last civil day the type told anything -
        /// "a never-told fact beats a told-and-since-changed one".
        var toldTypes: [String: String] = [:]
        /// rundown civil date -> assigned line identity for laid, not yet
        /// fired rundowns. Callback factIds verbatim; other Personal-Layer
        /// lines use the planner's marker strings ("obs:...",
        /// "anniversary:...", "deferred:...", "crushed").
        var scheduled: [String: String] = [:]
        /// callback type raw -> last civil day callback_evaluated logged
        /// (the once-per-type-per-user-day denominator cap).
        var lastEvaluated: [String: String] = [:]
        /// anniversary milestone id -> civil day the banner showed (the
        /// day's-first-open dedup).
        var bannerShown: [String: String] = [:]
        /// rundown civil date -> the opener line rendered when the
        /// assignment was made. Re-lays reuse it, so copy rotation burns
        /// once per assignment, not once per relay.
        var rendered: [String: String] = [:]
        /// Copy rotation for every Memories pool.
        var deck = CopyDeck()

        // MARK: Derived cadence queries (pure, planner-simulatable)

        /// Every factId that has consumed cadence: frozen tells plus the
        /// currently scheduled ones (scheduling consumes, per the spec).
        var consumedFactIds: Set<String> {
            var ids = Set(toldFacts.keys)
            for value in scheduled.values where CallbackFactID.isCallbackFactId(value) {
                ids.insert(value)
            }
            return ids
        }

        /// Civil days carrying a scheduled-or-told callback.
        var callbackDays: [CivilDay] {
            var days: [CivilDay] = []
            for (id, day) in toldFacts {
                if CallbackFactID.isCallbackFactId(id), let civil = CivilDay(day) {
                    days.append(civil)
                }
            }
            for (day, value) in scheduled where CallbackFactID.isCallbackFactId(value) {
                if let civil = CivilDay(day) { days.append(civil) }
            }
            return days
        }

        func callbackCount(inWeekOf day: CivilDay) -> Int {
            callbackDays.count { $0.weekKey == day.weekKey }
        }

        func nearestCallbackGap(to day: CivilDay) -> Int? {
            callbackDays.map { abs($0.dayNumber - day.dayNumber) }.min()
        }

        var everToldAnything: Bool {
            !toldTypes.isEmpty
        }
    }

    static let schemaVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(for userId: String) -> String {
        "mochi.memories.ledger.\(userId)"
    }

    // MARK: - State

    func state(userId: String) -> State {
        guard let data = defaults.data(forKey: Self.key(for: userId)),
              let stored = try? JSONDecoder().decode(State.self, from: data),
              stored.schemaVersion == Self.schemaVersion
        else { return State() }
        return stored
    }

    func save(_ state: State, userId: String) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.key(for: userId))
    }

    /// Account deletion clears the UID's cadence outright.
    func clear(userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    // MARK: - Commit

    /// Fold one relay's Personal-Layer assignment in: assignments whose
    /// date has passed freeze into the told record (their notification
    /// either fired or was the last thing laid for that morning), then
    /// today-and-future dates are replaced wholesale - a dropped future
    /// line un-consumes, because its notification was wiped before
    /// firing. Returns the values that are NEW per date, so callers log
    /// telemetry once per actual change, not once per relay.
    @discardableResult
    static func fold(
        assignments: [String: String],
        today: CivilDay,
        into state: inout State
    ) -> [String: String] {
        // Freeze the past.
        for (day, value) in state.scheduled {
            guard let civil = CivilDay(day), civil < today else { continue }
            if CallbackFactID.isCallbackFactId(value) {
                state.toldFacts[value] = day
                for type in factTypes(of: value) {
                    state.toldTypes[type.rawValue] = day
                }
            }
            state.scheduled.removeValue(forKey: day)
        }

        // Replace the future (and today).
        var changed: [String: String] = [:]
        var next: [String: String] = [:]
        for (day, value) in assignments {
            guard let civil = CivilDay(day), civil >= today else { continue }
            next[day] = value
            if state.scheduled[day] != value {
                changed[day] = value
            }
        }
        state.scheduled = next
        // Renderings follow their assignments: dropped or changed dates
        // lose the stored line (callers re-render the changed ones).
        state.rendered = state.rendered.filter { date, _ in
            next[date] != nil && changed[date] == nil
        }
        return changed
    }

    /// The types a canonical factId marks as having told. completion-day
    /// ids are deliberately shared between best day and date echo (the
    /// cross-type dedup), so they mark both histories.
    static func factTypes(of factId: String) -> [CallbackType] {
        if factId.hasPrefix("recovery-") { return [.recovery] }
        if factId.hasPrefix("streak-record-") { return [.streakEra] }
        if factId.hasPrefix("completion-day-") { return [.bestDay, .dateEcho] }
        return []
    }
}
