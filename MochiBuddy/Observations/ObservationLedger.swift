//
//  ObservationLedger.swift
//  MochiBuddy
//
//  Surfacing cadence ONLY (Personal Layer, Feature 4). Conclusions are
//  deterministic replays over synced data; nothing in here can change
//  one. The ledger owns: last-surfaced dates, the rundown weekly cap,
//  same-week letter/rundown dedup, copy rotation, the momentum cooldown,
//  and the once-per-type-per-day telemetry throttle.
//
//  Keys are namespaced per Firebase UID: sign-out leaves state inaccessible
//  (rekeyed on next sign-in), account switch starts a fresh cadence, and
//  deletion clears the UID's keys. Losing the ledger is never user-visible
//  beyond cadence - the conclusions themselves recompute identically.
//
//  A stored semantic-algorithm or schema version mismatch clears surfacing
//  state; ordinary Remote Config threshold tuning requires nothing.
//

import Foundation

@MainActor
final class ObservationLedger {

    enum Surface: String, Codable {
        case rundown
        case letter
        case journal
    }

    struct State: Codable, Equatable {
        var algorithmVersion: Int = ObservationConstants.algorithmVersion
        var schemaVersion: Int = ObservationLedger.schemaVersion
        /// kind.rawValue -> last civil day an observation_evaluated event
        /// was logged (the once-per-type-per-user-day denominator cap).
        var lastEvaluated: [String: String] = [:]
        /// conclusion key -> last civil day it surfaced anywhere.
        var lastSurfaced: [String: String] = [:]
        /// week key -> conclusion keys surfaced that week in a rundown or
        /// letter (the same-week dedup - hearing it twice reads as a script).
        var weekConclusions: [String: [String]] = [:]
        /// week key of the current rundown counting window.
        var rundownWeek: String = ""
        var rundownCount: Int = 0
        /// listId|firedOn keys of list-return events already surfaced -
        /// the event fires once, then expires.
        var surfacedReturnEvents: [String] = []
        var deck = CopyDeck()
    }

    static let schemaVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(for userId: String) -> String {
        "mochi.observations.ledger.\(userId)"
    }

    // MARK: - State

    func state(userId: String) -> State {
        guard let data = defaults.data(forKey: Self.key(for: userId)),
              let stored = try? JSONDecoder().decode(State.self, from: data),
              stored.algorithmVersion == ObservationConstants.algorithmVersion,
              stored.schemaVersion == Self.schemaVersion
        else {
            // Version gate: semantic algorithm changes invalidate cadence
            // state wholesale (conclusions may have changed meaning).
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

    // MARK: - Conclusion identity

    /// Stable identity for cadence bookkeeping. Never leaves the device
    /// and never reaches telemetry.
    static func conclusionKey(_ conclusion: ObservationConclusion) -> String {
        switch conclusion {
        case .weekday(let weekday): "weekday:\(weekday)"
        case .band(let band): "band:\(band.rawValue)"
        case .momentumRising: "momentum"
        case .listReturn(let listId): "listReturn:\(listId)"
        case .comeback: "comeback"
        }
    }

    // MARK: - Telemetry throttle

    /// True at most once per type per civil day - the denominator event's
    /// cap. Recording is part of asking, so a caller can't forget.
    func shouldLogEvaluation(kind: ObservationKind, day: String, userId: String) -> Bool {
        var state = state(userId: userId)
        guard state.lastEvaluated[kind.rawValue] != day else { return false }
        state.lastEvaluated[kind.rawValue] = day
        save(state, userId: userId)
        return true
    }

    // MARK: - Surfacing cadence

    /// Whether an observation may take a rundown line on a civil day: the
    /// weekly observation cap, and never the same conclusion a letter or
    /// rundown already used this week.
    func canSurfaceInRundown(_ observation: QualifiedObservation, on day: String, userId: String) -> Bool {
        // List return never takes a rundown line (its surfaces are letter
        // beats and the Journal, per the locked table).
        guard observation.kind != .listReturn else { return false }
        guard let civil = CivilDay(day) else { return false }
        let state = state(userId: userId)
        let key = Self.conclusionKey(observation.conclusion)
        if state.weekConclusions[civil.weekKey, default: []].contains(key) { return false }
        if state.rundownWeek == civil.weekKey,
           state.rundownCount >= ObservationConstants.rundownWeeklyCap {
            return false
        }
        if observation.kind == .momentum, momentumCoolingDown(on: civil, userId: userId) {
            return false
        }
        return true
    }

    /// Same-week dedup for letters: a conclusion a rundown already told
    /// this week doesn't reappear in the letter, and vice versa. Letter
    /// usage never counts against the rundown cap.
    func canSurfaceInLetter(_ observation: QualifiedObservation, on day: String, userId: String) -> Bool {
        guard let civil = CivilDay(day) else { return false }
        let state = state(userId: userId)
        let key = Self.conclusionKey(observation.conclusion)
        if state.weekConclusions[civil.weekKey, default: []].contains(key) { return false }
        if observation.kind == .listReturn {
            let eventKey = "\(key)|\(observation.stableSince)"
            if state.surfacedReturnEvents.contains(eventKey) { return false }
        }
        if observation.kind == .momentum, momentumCoolingDown(on: civil, userId: userId) {
            return false
        }
        return true
    }

    func recordSurfaced(
        _ observation: QualifiedObservation, surface: Surface, on day: String, userId: String
    ) {
        guard let civil = CivilDay(day) else { return }
        var state = state(userId: userId)
        let key = Self.conclusionKey(observation.conclusion)
        state.lastSurfaced[key] = day
        if surface != .journal {
            state.weekConclusions[civil.weekKey, default: []].append(key)
            // Weeks age out; only the current one ever matters again.
            state.weekConclusions = state.weekConclusions.filter { $0.key == civil.weekKey }
        }
        if surface == .rundown {
            if state.rundownWeek != civil.weekKey {
                state.rundownWeek = civil.weekKey
                state.rundownCount = 0
            }
            state.rundownCount += 1
        }
        if observation.kind == .listReturn {
            state.surfacedReturnEvents.append("\(key)|\(observation.stableSince)")
            // The event log stays tiny - old events have long expired.
            state.surfacedReturnEvents = Array(state.surfacedReturnEvents.suffix(20))
        }
        save(state, userId: userId)
    }

    /// The next copy line for a surfaced conclusion, rotating the
    /// persisted deck (round-robin, never repeat until the pool cycles).
    func nextLine(
        for conclusion: ObservationConclusion,
        petName: String,
        listName: String? = nil,
        userId: String
    ) -> String? {
        var state = state(userId: userId)
        let line = ObservationCopy.line(
            for: conclusion, petName: petName, listName: listName, deck: &state.deck
        )
        save(state, userId: userId)
        return line
    }

    /// The same line `nextLine` would render, WITHOUT rotating or saving -
    /// the lapsed Journal card renders its frozen conclusions through
    /// here so a read-only surface never advances cadence state
    /// (Feature 6: nothing composes during lapse).
    func peekLine(
        for conclusion: ObservationConclusion,
        petName: String,
        listName: String? = nil,
        userId: String
    ) -> String? {
        var deck = state(userId: userId).deck
        return ObservationCopy.line(
            for: conclusion, petName: petName, listName: listName, deck: &deck
        )
    }

    /// The civil day a conclusion last surfaced anywhere, nil if never -
    /// lets the Journal card keep a line visible on its surfacing day
    /// without re-recording it.
    func lastSurfacedDay(of conclusion: ObservationConclusion, userId: String) -> String? {
        state(userId: userId).lastSurfaced[Self.conclusionKey(conclusion)]
    }

    // MARK: - Momentum cooldown

    /// After momentum surfaces, it stays quiet for the cooldown window
    /// regardless of qualification.
    func momentumCoolingDown(on day: CivilDay, userId: String) -> Bool {
        let state = state(userId: userId)
        guard let last = state.lastSurfaced["momentum"],
              let lastDay = CivilDay(last)
        else { return false }
        return day.dayNumber - lastDay.dayNumber < ObservationConstants.trendCooldownDays
    }
}
