//
//  MoodForecast.swift
//  MochiBuddy
//
//  mood(t): the one engine, parameterized by time (design doc:
//  Notifications → Mood pings: technical requirements). A forecast is a
//  pre-evaluation of the same deterministic curve the app computes on
//  open, so a scheduled ping and mood(now) can never contradict each
//  other - the consistency invariant holds by construction, not sync.
//
//  The simulation bakes in every deterministic app-closed event: tasks
//  aging into overdue, recurring roll-forward + re-stamp (reusing
//  RecurrenceRoller, never a second implementation), momentum aging out,
//  buffer decay (reusing BufferBoost's own math), vacation auto-expiry,
//  and the horizon capped at the locally-known entitlement expiry so no
//  forecast reaches into a lapsed state.
//

import Foundation

/// Everything mood(t) needs, captured at one instant. Pure data - the
/// forecast never touches a repository or a clock.
struct MoodSnapshot {
    /// Incomplete tasks as loaded (already rolled forward to capturedAt).
    var tasks: [TaskItem] = []
    /// Completion times inside the momentum window before capturedAt.
    /// Timestamps, not a count, so momentum ages out mid-forecast.
    var completionTimes: [Date] = []
    /// Active pets/treats - the exact store type, so decay math is shared.
    var boosts: [BufferBoost] = []
    var vacationMode = false
    /// When vacation auto-expires; nil = open-ended (capped from startedAt).
    var vacationResumeAt: Date? = nil
    /// When the vacation began - drives the open-ended auto-expiry cap.
    var vacationStartedAt: Date? = nil
    /// Locally-known entitlement expiry - the hard forecast horizon.
    var entitlementExpiry: Date? = nil
    var capturedAt: Date
}

enum MoodForecast {

    /// Completions push momentum for this long (mirrors the 24h window the
    /// live surfaces count with).
    static let momentumWindow: TimeInterval = 24 * 3600
    /// Curve sampling step. Fine enough that a band transition between two
    /// samples is realistic to bisect; a dip-and-recover narrower than one
    /// step is beyond notification granularity and deliberately ignored.
    static let defaultResolution: TimeInterval = 15 * 60
    /// Band-crossing times are bisected down to this precision.
    static let crossingPrecision: TimeInterval = 60

    struct Sample: Equatable {
        let date: Date
        let value: Double
        let band: MoodBand
    }

    struct BandCrossing: Equatable {
        let date: Date
        let from: MoodBand
        let to: MoodBand
    }

    // MARK: - Point evaluation

    /// Baseline at a future instant: the live engine fed the simulated
    /// world - tasks rolled forward to t, momentum aged to t, vacation
    /// state advanced to t. No second predictor exists to drift.
    static func baseline(
        at t: Date,
        snapshot: MoodSnapshot,
        calendar: Calendar = .current
    ) -> Double {
        MoodEngine.baseline(
            incompleteTasks: tasks(at: t, snapshot: snapshot, calendar: calendar),
            completionsLast24h: completionCount(at: t, snapshot: snapshot),
            vacationMode: vacationActive(at: t, snapshot: snapshot),
            now: t,
            calendar: calendar
        )
    }

    /// Buffer at a future instant - each boost's own linear decay, summed
    /// and capped exactly like the store.
    static func buffer(at t: Date, snapshot: MoodSnapshot) -> Double {
        let total = snapshot.boosts.reduce(0) { $0 + $1.value(at: t) }
        return min(MoodEngine.Constants.bufferCap, total)
    }

    /// The displayed value (baseline + buffer) - what mood pings and the
    /// widget forecast against, per the doc: forecast the displayed value.
    static func displayed(
        at t: Date,
        snapshot: MoodSnapshot,
        calendar: Calendar = .current
    ) -> Double {
        min(100, max(0, baseline(at: t, snapshot: snapshot, calendar: calendar)
            + buffer(at: t, snapshot: snapshot)))
    }

    static func band(
        at t: Date,
        snapshot: MoodSnapshot,
        calendar: Calendar = .current
    ) -> MoodBand {
        MoodBand(value: displayed(at: t, snapshot: snapshot, calendar: calendar))
    }

    // MARK: - Horizon

    /// The requested horizon, hard-capped at entitlement expiry so no
    /// mood ping is ever laid into a lapsed state.
    static func horizonEnd(requested: Date, snapshot: MoodSnapshot) -> Date {
        guard let expiry = snapshot.entitlementExpiry else { return requested }
        return min(requested, expiry)
    }

    // MARK: - Curve & crossings

    /// The displayed-value curve from capture to the (capped) horizon.
    static func curve(
        until requestedEnd: Date,
        snapshot: MoodSnapshot,
        resolution: TimeInterval = defaultResolution,
        calendar: Calendar = .current
    ) -> [Sample] {
        let end = horizonEnd(requested: requestedEnd, snapshot: snapshot)
        guard end > snapshot.capturedAt else { return [] }

        var samples: [Sample] = []
        var t = snapshot.capturedAt
        while t < end {
            samples.append(sample(at: t, snapshot: snapshot, calendar: calendar))
            t = t.addingTimeInterval(resolution)
        }
        samples.append(sample(at: end, snapshot: snapshot, calendar: calendar))
        return samples
    }

    /// Every band transition inside the horizon, in order, each located to
    /// within `crossingPrecision`. Handles a plunge through several bands
    /// inside one sampling step by re-anchoring after each found crossing.
    static func bandCrossings(
        until requestedEnd: Date,
        snapshot: MoodSnapshot,
        resolution: TimeInterval = defaultResolution,
        calendar: Calendar = .current
    ) -> [BandCrossing] {
        let samples = curve(
            until: requestedEnd, snapshot: snapshot,
            resolution: resolution, calendar: calendar
        )
        guard var anchor = samples.first else { return [] }

        var crossings: [BandCrossing] = []
        for next in samples.dropFirst() {
            // Multiple bands can be crossed within one step - keep
            // bisecting from the last found crossing until the step's end
            // band is reached.
            while anchor.band != next.band {
                let crossing = bisectCrossing(
                    from: anchor, toDate: next.date,
                    snapshot: snapshot, calendar: calendar
                )
                crossings.append(crossing)
                anchor = sample(at: crossing.date, snapshot: snapshot, calendar: calendar)
            }
            anchor = next
        }
        return crossings
    }

    // MARK: - Internals

    private static func sample(
        at t: Date,
        snapshot: MoodSnapshot,
        calendar: Calendar
    ) -> Sample {
        let value = displayed(at: t, snapshot: snapshot, calendar: calendar)
        return Sample(date: t, value: value, band: MoodBand(value: value))
    }

    /// Earliest instant in (anchor.date, toDate] where the band differs
    /// from the anchor's, to within crossingPrecision.
    private static func bisectCrossing(
        from anchor: Sample,
        toDate: Date,
        snapshot: MoodSnapshot,
        calendar: Calendar
    ) -> BandCrossing {
        var lo = anchor.date
        var hi = toDate
        var hiBand = band(at: hi, snapshot: snapshot, calendar: calendar)
        while hi.timeIntervalSince(lo) > crossingPrecision {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            let midBand = band(at: mid, snapshot: snapshot, calendar: calendar)
            if midBand == anchor.band {
                lo = mid
            } else {
                hi = mid
                hiBand = midBand
            }
        }
        return BandCrossing(date: hi, from: anchor.band, to: hiBand)
    }

    private static func tasks(
        at t: Date,
        snapshot: MoodSnapshot,
        calendar: Calendar
    ) -> [TaskItem] {
        snapshot.tasks.map { task in
            // The exact roll the app applies on open, simulated - if a
            // recurring task would have rolled while closed, its stress
            // contribution is re-capped here too.
            RecurrenceRoller.restamp(task, now: t, calendar: calendar)?.task ?? task
        }
    }

    private static func completionCount(at t: Date, snapshot: MoodSnapshot) -> Int {
        snapshot.completionTimes.count { time in
            time >= t.addingTimeInterval(-momentumWindow) && time <= t
        }
    }

    private static func vacationActive(at t: Date, snapshot: MoodSnapshot) -> Bool {
        // The one shared auto-expiry rule - never a forecast-local copy.
        VacationSchedule.isActive(
            mode: snapshot.vacationMode,
            startedAt: snapshot.vacationStartedAt,
            resumeAt: snapshot.vacationResumeAt,
            at: t
        )
    }
}
