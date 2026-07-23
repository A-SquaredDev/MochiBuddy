//
//  WidgetState.swift
//  MochiShared
//
//  The App Group data contract (design doc: Widgets → App Group data
//  contract). The app owns all writes; the widget only reads. The stored
//  forecast is the BASELINE curve from the one mood engine - the widget
//  adds the live comfort buffer on top with the same shared math, so a
//  pet from the home screen moves the face without any engine on board.
//

import Foundation

enum MochiAppGroup {
    static let id = "group.com.aaronmckain.MochiBuddy"

    /// The shared suite; standard defaults as a last-resort fallback so a
    /// missing entitlement degrades to app-only behavior, never a crash.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

struct MochiWidgetState: Codable, Equatable {

    enum DisplayState: String, Codable {
        case active
        /// Asleep, "Wake Mochi" resubscribe CTA, tasks still completable.
        case lapsed
        /// Resting, "On vacation" hint + end date, never the wake CTA -
        /// the two calm states stay distinct (locked decision).
        case vacation

        /// The locked state-variant table (design doc: Widgets). Complete
        /// stays available in EVERY state: lapsed keeps existing tasks
        /// completable, vacation removes pressure, not function.
        var allowsComplete: Bool { true }
        /// Tap-to-pet is active-only - never on a napping or resting Mochi.
        var allowsPet: Bool { self == .active }
    }

    /// One sample of the baseline mood(t) curve (no buffer baked in).
    struct ForecastPoint: Codable, Equatable {
        var date: Date
        var value: Double
    }

    struct NextTask: Codable, Equatable {
        var id: String
        var title: String
        var dueAt: Date?
        var hasTime: Bool
        var completable: Bool
    }

    var schemaVersion = 1
    var displayState: DisplayState
    var themeId: String
    /// The pet's name. Optional so a pre-rename snapshot still decodes;
    /// the widget falls back to "Mochi" via `petDisplayName`, making the
    /// app-first update order safe.
    var mochiName: String? = nil
    /// Baseline samples, ascending - the notification forecast's curve,
    /// mirrored verbatim.
    var baseline: [ForecastPoint]
    var hideTaskNames: Bool
    /// Top 1-3 by the morning-rundown ranking.
    var nextTasks: [NextTask]
    var vacationEnd: Date?
    var lastComputed: Date

    /// What widget chrome and VoiceOver call the pet.
    var petDisplayName: String {
        mochiName ?? "Mochi"
    }

    // MARK: - Widget-side evaluation

    /// Baseline at an instant: linear interpolation between samples,
    /// clamped to the ends (the curve is piecewise-smooth at the stored
    /// resolution, so lerp is faithful).
    func baselineValue(at date: Date) -> Double {
        guard let first = baseline.first else { return 58 }
        guard date > first.date else { return first.value }
        guard let last = baseline.last, date < last.date else {
            return baseline.last?.value ?? first.value
        }
        for (a, b) in zip(baseline, baseline.dropFirst()) where date <= b.date {
            let span = b.date.timeIntervalSince(a.date)
            guard span > 0 else { return b.value }
            let t = date.timeIntervalSince(a.date) / span
            return a.value + (b.value - a.value) * t
        }
        return last.value
    }

    /// What the face shows: baseline plus the live buffer, same clamp as
    /// everywhere else.
    func displayedValue(at date: Date, boosts: [BufferBoost]) -> Double {
        let buffer = min(MochiComfort.bufferCap, boosts.reduce(0) { $0 + $1.value(at: date) })
        return min(100, max(0, baselineValue(at: date) + buffer))
    }
}

/// Reads/writes the contract in the shared suite, plus the tiny queue a
/// widget Complete rides until the app opens and makes it durable.
enum WidgetStateStore {

    static let stateKey = "mochi.widget.state"
    static let completionQueueKey = "mochi.widget.pendingCompletions"

    static func load(defaults: UserDefaults = MochiAppGroup.defaults) -> MochiWidgetState? {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(MochiWidgetState.self, from: data),
              state.schemaVersion == 1
        else { return nil }
        return state
    }

    static func save(_ state: MochiWidgetState, defaults: UserDefaults = MochiAppGroup.defaults) {
        defaults.set(try? JSONEncoder().encode(state), forKey: stateKey)
    }

    // MARK: - Complete-from-widget queue

    /// A widget completion queues here (and optimistically updates the
    /// snapshot); the app drains it into the source of truth on next open.
    static func enqueueCompletion(taskId: String, defaults: UserDefaults = MochiAppGroup.defaults) {
        var queue = defaults.stringArray(forKey: completionQueueKey) ?? []
        guard !queue.contains(taskId) else { return }
        queue.append(taskId)
        defaults.set(queue, forKey: completionQueueKey)
    }

    static func pendingCompletions(defaults: UserDefaults = MochiAppGroup.defaults) -> [String] {
        defaults.stringArray(forKey: completionQueueKey) ?? []
    }

    /// Read-and-clear, for the app-side drain.
    static func drainCompletions(defaults: UserDefaults = MochiAppGroup.defaults) -> [String] {
        let queue = pendingCompletions(defaults: defaults)
        defaults.removeObject(forKey: completionQueueKey)
        return queue
    }
}
