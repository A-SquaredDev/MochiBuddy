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

/// Where in their own day the user completed a task, captured at the
/// moment of completion (Personal Layer, Feature 4). Behavior is a fact
/// about the day it happened in; re-deriving it later from the UTC
/// instant plus the device's CURRENT zone would let travel rewrite
/// history. Lives in MochiShared so a widget completion stamps its
/// context at tap time, not at next-open drain time.
struct CompletionLocalContext: Codable, Equatable {
    /// YYYY-MM-DD in the zone where completed.
    let localDate: String
    /// Minutes since local midnight, 0...1439.
    let localMinute: Int
    /// IANA identifier of the zone at completion.
    let timeZoneId: String

    static func capture(at instant: Date = .now, timeZone: TimeZone = .current) -> CompletionLocalContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        return CompletionLocalContext(
            localDate: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
            localMinute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
            timeZoneId: timeZone.identifier
        )
    }

    /// The absolute instant this context was stamped at, rebuilt from the
    /// local fields (minute precision). Fallback for queue entries written
    /// before the tap instant itself was recorded.
    var approximateInstant: Date? {
        guard let zone = TimeZone(identifier: timeZoneId) else { return nil }
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2],
            hour: localMinute / 60, minute: localMinute % 60
        ))
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

    /// Every instant in (start, end] where the widget's rendering would
    /// visibly change: the displayed value crossing a label band (MoodBand)
    /// or face bucket (MochiMood) boundary - whether driven by the stored
    /// curve or by a boost fading out. Scanned at `resolution`, each change
    /// bisected to the minute; a plunge through several boundaries inside
    /// one step yields one date per boundary. Returned dates sit on the NEW
    /// side of their crossing, so a timeline entry there renders the new
    /// mood.
    func visibleMoodChanges(
        from start: Date,
        until end: Date,
        boosts: [BufferBoost],
        resolution: TimeInterval = 5 * 60
    ) -> [Date] {
        guard end > start else { return [] }
        func look(_ date: Date) -> (MoodBand, MochiMood) {
            let value = displayedValue(at: date, boosts: boosts)
            return (MoodBand(value: value), MochiMood(vitality: value))
        }

        var changes: [Date] = []
        var anchor = start
        var anchorLook = look(start)
        var t = start
        while t < end {
            t = min(t.addingTimeInterval(resolution), end)
            let stepLook = look(t)
            while anchorLook != stepLook {
                var lo = anchor
                var hi = t
                var hiLook = stepLook
                while hi.timeIntervalSince(lo) > 60 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    let midLook = look(mid)
                    if midLook == anchorLook {
                        lo = mid
                    } else {
                        hi = mid
                        hiLook = midLook
                    }
                }
                changes.append(hi)
                anchor = hi
                anchorLook = hiLook
            }
            anchor = t
            anchorLook = stepLook
        }
        return changes
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

    /// One queued widget completion, local context stamped at tap time so
    /// an overnight drain can never shift evening behavior into morning.
    /// Context is nil only for entries queued by a pre-context app version;
    /// the drain then falls back to derived context, honestly marked.
    /// tappedAt is the absolute tap instant, so completedAt lands truthful
    /// even when the drain runs days later; nil on entries queued by an
    /// older version (the drain falls back to context.approximateInstant).
    struct PendingCompletion: Codable, Equatable {
        let taskId: String
        let context: CompletionLocalContext?
        var tappedAt: Date? = nil
    }

    /// A widget completion queues here (and optimistically updates the
    /// snapshot); the app drains it into the source of truth on next open.
    static func enqueueCompletion(
        taskId: String,
        context: CompletionLocalContext,
        tappedAt: Date = .now,
        defaults: UserDefaults = MochiAppGroup.defaults
    ) {
        var queue = decodedQueue(defaults: defaults)
        guard !queue.contains(where: { $0.taskId == taskId }) else { return }
        queue.append(PendingCompletion(taskId: taskId, context: context, tappedAt: tappedAt))
        defaults.set(try? JSONEncoder().encode(queue), forKey: completionQueueKey)
    }

    static func pendingCompletions(defaults: UserDefaults = MochiAppGroup.defaults) -> [PendingCompletion] {
        decodedQueue(defaults: defaults)
    }

    /// Read-and-clear, for the app-side drain.
    static func drainCompletions(defaults: UserDefaults = MochiAppGroup.defaults) -> [PendingCompletion] {
        let queue = pendingCompletions(defaults: defaults)
        defaults.removeObject(forKey: completionQueueKey)
        return queue
    }

    /// Current queue plus any entries from the pre-context string-array
    /// format (an update can land between a tap and the next open); legacy
    /// ids carry no context and fall back at drain time.
    private static func decodedQueue(defaults: UserDefaults) -> [PendingCompletion] {
        if let legacy = defaults.stringArray(forKey: completionQueueKey) {
            return legacy.map {
                PendingCompletion(taskId: $0, context: nil)
            }
        }
        guard let data = defaults.data(forKey: completionQueueKey),
              let queue = try? JSONDecoder().decode([PendingCompletion].self, from: data)
        else { return [] }
        return queue
    }
}
