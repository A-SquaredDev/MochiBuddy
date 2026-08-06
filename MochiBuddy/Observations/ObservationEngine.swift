//
//  ObservationEngine.swift
//  MochiBuddy
//
//  The pure insight engine (Personal Layer, Feature 4): completion stats
//  in, things Mochi NOTICED out. No UI of its own - it feeds letter beats,
//  rundown lines, the Journal card, and Feature 5's suggested times.
//
//  Everything here is a pure function of its inputs: calendar and "now"
//  arrive as explicit parameters (no .autoupdatingCurrent, no clock reads),
//  records carry their own completion-local context, and stability is a
//  deterministic replay over synced data - so every device computes the
//  same conclusions by construction, and "same inputs, same output" is
//  literally true.
//
//  When unsure, say nothing. A failed gate produces silence, never a
//  hedged guess; a falling trend produces NO observation, not a concerned
//  one. Negative patterns are not observations; they are silence.
//

import Foundation

// MARK: - Civil days

/// A calendar date with no zone attached - the currency of the engine.
/// Completion records name the civil day they happened in (in the zone
/// where they happened); all window arithmetic is day arithmetic on these.
/// Backed by a fixed UTC Gregorian calendar so parse, arithmetic, and
/// weekday can never disagree across devices.
struct CivilDay: Hashable, Comparable {

    /// Days since 1970-01-01.
    let dayNumber: Int

    private static var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private static var isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    /// From YYYY-MM-DD; nil for malformed strings. Calendar silently rolls
    /// invalid dates forward (month 13 becomes January) - the round-trip
    /// mismatch is how we detect them.
    init?(_ string: String) {
        let pieces = string.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]),
              let date = Self.utcCalendar.date(
                  from: DateComponents(year: year, month: month, day: day, hour: 12)
              )
        else { return nil }
        let echo = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard echo.year == year, echo.month == month, echo.day == day else { return nil }
        dayNumber = Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    /// The civil day of an instant as seen from the caller's calendar -
    /// used ONLY where the model says to (snapshot days, interval days),
    /// never to re-bucket records that carry their own local context.
    init(of instant: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        let anchor = Self.utcCalendar.date(
            from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)
        ) ?? Date(timeIntervalSince1970: 0)
        dayNumber = Int(floor(anchor.timeIntervalSince1970 / 86_400))
    }

    /// Noon UTC of the day - safe anchor for component math.
    private var anchor: Date {
        Date(timeIntervalSince1970: TimeInterval(dayNumber) * 86_400 + 43_200)
    }

    var dateString: String {
        let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: anchor)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Calendar weekday numbering, 1 = Sunday ... 7 = Saturday.
    var weekday: Int {
        Self.utcCalendar.component(.weekday, from: anchor)
    }

    /// ISO week identity for the spread gates.
    var weekKey: String {
        let parts = Self.isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    func advanced(by days: Int) -> CivilDay {
        CivilDay(dayNumber: dayNumber + days)
    }

    static func < (lhs: CivilDay, rhs: CivilDay) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }
}

// MARK: - Engine

enum ObservationEngine {

    struct Inputs {
        var records: [CompletedTaskStat]
        var intervals: [ObservationInterval]
        /// When the interval log began; days before it have UNKNOWN
        /// eligibility (momentum's honest-fallback rule).
        var logSince: Date?
        /// Lists that still exist - list-scoped outputs only ever
        /// reference surviving ids.
        var knownListIds: Set<String>
        /// The device's current calendar+zone, passed explicitly. Applied
        /// only where the model says to: snapshot days and interval days.
        var calendar: Calendar
        var now: Date
    }

    struct Snapshot: Equatable {
        /// Today's gate evaluation for every type - inspector + tests only.
        var candidates: [ObservationCandidate]
        /// The only output production surfaces may consume.
        var qualified: [QualifiedObservation]
        /// Replay timelines for the trait types - flapping made visible.
        var timelines: [ObservationReplayTimeline]
    }

    // MARK: Entry points

    static func evaluate(_ inputs: Inputs) -> Snapshot {
        let prepared = Prepared(inputs: inputs)
        let today = prepared.today

        var candidates: [ObservationCandidate] = []
        var qualified: [QualifiedObservation] = []
        var timelines: [ObservationReplayTimeline] = []

        // Trait types: today's candidate for the inspector, the replayed
        // incumbent for production.
        for kind in [ObservationKind.weekday, .timeOfDay, .comeback] {
            candidates.append(traitCandidate(kind, at: today, prepared: prepared))
            let timeline = replay(kind, endingAt: today, prepared: prepared)
            timelines.append(timeline)
            if let incumbent = timeline.incumbent, let since = timeline.stableSince {
                qualified.append(QualifiedObservation(
                    kind: kind, conclusion: incumbent, stableSince: since
                ))
            }
        }

        // Momentum: a compose-time fact - qualifies now or not at all.
        let momentum = momentumCandidate(at: today, prepared: prepared)
        candidates.append(momentum)
        if momentum.passesAllGates {
            qualified.append(QualifiedObservation(
                kind: .momentum, conclusion: .momentumRising, stableSince: today.dateString
            ))
        }

        // List return: an event - fires, surfaces within the week, expires.
        let listReturn = listReturnCandidate(at: today, prepared: prepared)
        candidates.append(listReturn.candidate)
        if listReturn.candidate.passesAllGates,
           let conclusion = listReturn.candidate.conclusion,
           let firedOn = listReturn.firedOn {
            qualified.append(QualifiedObservation(
                kind: .listReturn, conclusion: conclusion, stableSince: firedOn.dateString
            ))
        }

        return Snapshot(candidates: candidates, qualified: qualified, timelines: timelines)
    }

    /// Feature 5's contract. Provenance is explicit: when the list alone
    /// is below the evidence floor the result says `.globalFallback` - a
    /// caller can never mistake a fallback for list evidence.
    static func timeOfDayDistribution(listId: String?, inputs: Inputs) -> DistributionResult {
        let prepared = Prepared(inputs: inputs)
        let window = prepared.windowRecords(endingAt: prepared.today)

        if let listId {
            let scoped = window.filter { $0.stat.listId == listId }
            let capped = dayCappedEntries(scoped)
            if capped.count >= ObservationConstants.timeOfDayMin {
                return DistributionResult(entries: capped, scopeUsed: .list(listId))
            }
        }
        return DistributionResult(entries: dayCappedEntries(window), scopeUsed: .globalFallback)
    }

    /// A suggestion scope, named by the caller (Feature 5). Unlike the
    /// Feature 4 contract above there is NO fallback logic here: scope
    /// precedence is Feature 5's qualification job, and each scope's
    /// result honestly names itself.
    enum SuggestionScope {
        case series(String)
        case list(String)
        case global
    }

    /// Raw per-scope distribution for suggested times (Feature 5).
    /// Series scope keeps TIMED completions only (the spec's "timed
    /// completions" gate: a series' due time is what re-time proposes to
    /// change, so undated and date-only rows are not evidence about it).
    /// Day capping runs AFTER scope filtering, the Feature 4 order - a
    /// scope's cap is a fact about that scope's own days.
    static func suggestionDistribution(scope: SuggestionScope, inputs: Inputs) -> DistributionResult {
        let prepared = Prepared(inputs: inputs)
        let window = prepared.windowRecords(endingAt: prepared.today)
        let scoped: [PreparedRecord]
        let scopeUsed: DistributionResult.Scope
        switch scope {
        case .series(let identity):
            scoped = window.filter { $0.seriesKey == identity && $0.stat.hasTime }
            scopeUsed = .series(identity)
        case .list(let listId):
            scoped = window.filter { $0.stat.listId == listId }
            scopeUsed = .list(listId)
        case .global:
            scoped = window
            scopeUsed = .globalFallback
        }
        return DistributionResult(entries: dayCappedEntries(scoped), scopeUsed: scopeUsed)
    }

    /// Circular center of minute-of-day values: 23:30 and 00:30 cluster
    /// to midnight, never to noon. Nil for an empty set.
    static func circularCenterMinute(of minutes: [Int]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        var sinSum = 0.0
        var cosSum = 0.0
        for minute in minutes {
            let angle = Double(minute) / 1440 * 2 * .pi
            sinSum += sin(angle)
            cosSum += cos(angle)
        }
        // All points evenly opposed: no meaningful center.
        guard sinSum * sinSum + cosSum * cosSum > 1e-9 else { return nil }
        var angle = atan2(sinSum, cosSum)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * 1440).rounded()) % 1440
    }

    // MARK: - Preprocessing

    struct PreparedRecord {
        let stat: CompletedTaskStat
        /// The civil day the completion happened in, IN ITS OWN ZONE.
        let day: CivilDay
        let band: TimeOfDayBand
        /// Excluded from the weekday observation unless one-off - a
        /// weekly-Tuesday task must not mint "productive on Tuesdays".
        let isOneOff: Bool
        /// One habit is one identity for the diversity gates.
        let seriesKey: String
        /// Seconds late past the overdue boundary; nil = not a comeback
        /// event (undated, or completed on time).
        let lateness: TimeInterval?
    }

    struct Prepared {
        let records: [PreparedRecord]
        let today: CivilDay
        /// Days inside vacation/lapse intervals, under the caller's zone.
        let ineligibleDays: Set<CivilDay>
        /// Days before this one predate the interval log: eligibility
        /// unknown. Nil when the log has never been stamped (everything
        /// unknown).
        let knownSince: CivilDay?
        let knownListIds: Set<String>

        init(inputs: Inputs) {
            today = CivilDay(of: inputs.now, in: inputs.calendar)
            knownListIds = inputs.knownListIds
            knownSince = inputs.logSince.map { CivilDay(of: $0, in: inputs.calendar) }

            var ineligible: Set<CivilDay> = []
            for interval in inputs.intervals {
                let start = CivilDay(of: interval.start, in: inputs.calendar)
                let end = CivilDay(of: min(interval.end ?? inputs.now, inputs.now), in: inputs.calendar)
                var day = start
                while day <= end {
                    ineligible.insert(day)
                    day = day.advanced(by: 1)
                }
            }
            ineligibleDays = ineligible

            records = inputs.records.compactMap { stat in
                guard let day = CivilDay(stat.completedLocalDate) else { return nil }
                var lateness: TimeInterval?
                if let dueAt = stat.dueAt {
                    let boundary: Date
                    if stat.hasTime {
                        boundary = dueAt
                    } else {
                        // The existing overdue rule: date-only tasks flip
                        // at the end of the due day - evaluated in the
                        // record's own completion zone, deterministically.
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = TimeZone(identifier: stat.completionTimeZone)
                            ?? TimeZone(identifier: "UTC")!
                        boundary = calendar.startOfDay(for: dueAt).addingTimeInterval(86_400)
                    }
                    let late = stat.completedAt.timeIntervalSince(boundary)
                    lateness = late > 0 ? late : nil
                }
                return PreparedRecord(
                    stat: stat,
                    day: day,
                    band: TimeOfDayBand(minute: stat.completedLocalMinute),
                    isOneOff: !stat.isRecurring && stat.seriesId == nil,
                    seriesKey: stat.seriesId ?? stat.taskId,
                    lateness: lateness
                )
            }
        }

        /// Records inside the evidence window ending at a snapshot day.
        func windowRecords(endingAt snapshot: CivilDay) -> [PreparedRecord] {
            let start = snapshot.advanced(by: -(ObservationConstants.windowDays - 1))
            return records.filter { $0.day >= start && $0.day <= snapshot }
        }

        func eligibility(of day: CivilDay) -> DayEligibility {
            guard let knownSince, day >= knownSince else { return .unknown }
            return ineligibleDays.contains(day) ? .ineligible : .eligible
        }
    }

    enum DayEligibility {
        case eligible
        case ineligible
        case unknown
    }

    // MARK: - Shared counting

    /// Day-capped counts per key: each calendar day contributes at most
    /// `dayCap` completions per key, so one heroic burst can't dominate.
    private static func cappedCounts<Key: Hashable>(
        _ records: [PreparedRecord], by key: (PreparedRecord) -> Key
    ) -> (counts: [Key: Int], contributingDays: Set<CivilDay>) {
        var perDayKey: [CivilDay: [Key: Int]] = [:]
        for record in records {
            perDayKey[record.day, default: [:]][key(record), default: 0] += 1
        }
        var counts: [Key: Int] = [:]
        var days: Set<CivilDay> = []
        for (day, keyed) in perDayKey {
            days.insert(day)
            for (key, count) in keyed {
                counts[key, default: 0] += Swift.min(count, ObservationConstants.dayCap)
            }
        }
        return (counts, days)
    }

    /// Day-capped distribution entries. Within a day, picks are stride-
    /// sampled over the minute-sorted records (first, spread, last) so the
    /// cap limits weight without biasing toward one end of the day.
    private static func dayCappedEntries(_ records: [PreparedRecord]) -> [DistributionResult.Entry] {
        var perDay: [CivilDay: [PreparedRecord]] = [:]
        for record in records {
            perDay[record.day, default: []].append(record)
        }
        var entries: [DistributionResult.Entry] = []
        for day in perDay.keys.sorted() {
            let sorted = perDay[day]!.sorted { $0.stat.completedLocalMinute < $1.stat.completedLocalMinute }
            let cap = ObservationConstants.dayCap
            var picks: [PreparedRecord] = []
            if sorted.count <= cap {
                picks = sorted
            } else {
                for pick in 0..<cap {
                    let index = pick * (sorted.count - 1) / Swift.max(cap - 1, 1)
                    picks.append(sorted[index])
                }
            }
            entries.append(contentsOf: picks.map { record in
                DistributionResult.Entry(
                    minute: record.stat.completedLocalMinute,
                    day: record.day.dateString,
                    identity: record.seriesKey,
                    rescheduleCount: record.stat.rescheduleCount
                )
            })
        }
        return entries
    }

    // MARK: - Trait gates (single snapshot)

    /// The best conclusion and its gate story at one snapshot day.
    static func traitCandidate(
        _ kind: ObservationKind, at snapshot: CivilDay, prepared: Prepared
    ) -> ObservationCandidate {
        switch kind {
        case .weekday: weekdayCandidate(at: snapshot, prepared: prepared)
        case .timeOfDay: timeOfDayCandidate(at: snapshot, prepared: prepared)
        case .comeback: comebackCandidate(at: snapshot, prepared: prepared)
        // Event kinds (.momentum, .listReturn) have no single-snapshot
        // trait candidate; an empty candidate keeps a mistaken caller
        // from crashing the app.
        default: ObservationCandidate(
            kind: kind, conclusion: nil, gates: [], evidenceCount: 0, topShare: nil
        )
        }
    }

    private static func weekdayCandidate(
        at snapshot: CivilDay, prepared: Prepared
    ) -> ObservationCandidate {
        // One-off completions only - the circularity trap, designed out.
        let oneOffs = prepared.windowRecords(endingAt: snapshot).filter(\.isOneOff)
        let (counts, days) = cappedCounts(oneOffs) { $0.day.weekday }
        let total = counts.values.reduce(0, +)
        let weeks = Set(days.map(\.weekKey)).count

        // Deterministic top pick: highest count, lowest weekday breaks ties
        // (the margin gate fails on a real tie anyway).
        let ranked = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        let top = ranked.first
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let share = total > 0 ? Double(top?.value ?? 0) / Double(total) : 0

        let gates = [
            gate("evidence floor", count: total, atLeast: ObservationConstants.weekdayMin),
            gate("distinct weeks", count: weeks, atLeast: ObservationConstants.weekdayWeeks),
            gate("top share", share: share, atLeast: ObservationConstants.weekdayShare),
            marginGate(top: top?.value ?? 0, runnerUp: runnerUp),
        ]
        return ObservationCandidate(
            kind: .weekday,
            conclusion: top.map { .weekday($0.key) },
            gates: gates,
            evidenceCount: total,
            topShare: total > 0 ? share : nil
        )
    }

    private static func timeOfDayCandidate(
        at snapshot: CivilDay, prepared: Prepared
    ) -> ObservationCandidate {
        // ALL completions: when in the day the user acts is genuine
        // behavior even for scheduled tasks.
        let window = prepared.windowRecords(endingAt: snapshot)
        let (counts, days) = cappedCounts(window) { $0.band }
        let total = counts.values.reduce(0, +)
        let weeks = Set(days.map(\.weekKey)).count

        let ranked = counts.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
        let top = ranked.first
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let share = total > 0 ? Double(top?.value ?? 0) / Double(total) : 0

        let gates = [
            gate("evidence floor", count: total, atLeast: ObservationConstants.timeOfDayMin),
            gate("distinct dates", count: days.count, atLeast: ObservationConstants.timeOfDayDates),
            gate("distinct weeks", count: weeks, atLeast: ObservationConstants.timeOfDayWeeks),
            gate("top share", share: share, atLeast: ObservationConstants.timeOfDayShare),
            marginGate(top: top?.value ?? 0, runnerUp: runnerUp),
        ]
        return ObservationCandidate(
            kind: .timeOfDay,
            conclusion: top.map { .band($0.key) },
            gates: gates,
            evidenceCount: total,
            topShare: total > 0 ? share : nil
        )
    }

    private static func comebackCandidate(
        at snapshot: CivilDay, prepared: Prepared
    ) -> ObservationCandidate {
        let events = prepared.windowRecords(endingAt: snapshot).filter { $0.lateness != nil }
        let latenesses = events.compactMap(\.lateness).sorted()
        let dates = Set(events.map(\.day)).count
        let identities = Set(events.map(\.seriesKey)).count

        let median = median(of: latenesses)
        let p75 = percentile75(of: latenesses)
        let medianCap = ObservationConstants.comebackHours * 3600
        let p75Cap = ObservationConstants.comebackP75Hours * 3600

        let gates = [
            gate("evidence floor", count: events.count, atLeast: ObservationConstants.comebackMin),
            gate("distinct dates", count: dates, atLeast: ObservationConstants.comebackDates),
            gate("distinct tasks", count: identities, atLeast: ObservationConstants.comebackTasks),
            ObservationGateCheck(
                name: "median catch-up",
                achieved: hoursText(median),
                required: "<= \(hoursText(medianCap))",
                passed: median != nil && median! <= medianCap
            ),
            ObservationGateCheck(
                name: "p75 catch-up",
                achieved: hoursText(p75),
                required: "<= \(hoursText(p75Cap))",
                passed: p75 != nil && p75! <= p75Cap
            ),
        ]
        return ObservationCandidate(
            kind: .comeback,
            conclusion: events.isEmpty ? nil : .comeback,
            gates: gates,
            evidenceCount: events.count,
            topShare: nil
        )
    }

    // MARK: - Momentum (compose-time fact)

    static func momentumCandidate(
        at snapshot: CivilDay, prepared: Prepared
    ) -> ObservationCandidate {
        let half = ObservationConstants.windowDays / 2
        let windowStart = snapshot.advanced(by: -(ObservationConstants.windowDays - 1))
        let recentStart = snapshot.advanced(by: -(half - 1))

        // Vacation/lapse days leave momentum ENTIRELY - the day and its
        // completions together; and any day of unknown eligibility keeps
        // the whole observation silent (the honest-fallback rule).
        var unknownDays = 0
        var olderDays = 0, recentDays = 0
        var eligibleDaySet: Set<CivilDay> = []
        var day = windowStart
        while day <= snapshot {
            switch prepared.eligibility(of: day) {
            case .unknown:
                unknownDays += 1
            case .ineligible:
                break
            case .eligible:
                eligibleDaySet.insert(day)
                if day >= recentStart { recentDays += 1 } else { olderDays += 1 }
            }
            day = day.advanced(by: 1)
        }

        let window = prepared.windowRecords(endingAt: snapshot)
        let olderCount = window.filter { $0.day < recentStart && eligibleDaySet.contains($0.day) }.count
        let recentCount = window.filter { $0.day >= recentStart && eligibleDaySet.contains($0.day) }.count

        let olderRate = olderDays > 0 ? Double(olderCount) / Double(olderDays) : 0
        let recentRate = recentDays > 0 ? Double(recentCount) / Double(recentDays) : 0
        let ratioOK = olderRate > 0 && recentRate >= ObservationConstants.trendRatio * olderRate
        let delta = recentRate - olderRate

        let gates = [
            ObservationGateCheck(
                name: "eligibility known",
                achieved: unknownDays == 0 ? "all days known" : "\(unknownDays) days predate the log",
                required: "0 unknown days",
                passed: unknownDays == 0
            ),
            gate("older half floor", count: olderCount, atLeast: ObservationConstants.trendHalfMin),
            gate("recent half floor", count: recentCount, atLeast: ObservationConstants.trendHalfMin),
            ObservationGateCheck(
                name: "rate ratio",
                achieved: String(format: "%.2f/day vs %.2f/day", recentRate, olderRate),
                required: String(format: ">= %.1fx", ObservationConstants.trendRatio),
                passed: ratioOK
            ),
            ObservationGateCheck(
                name: "absolute delta",
                achieved: String(format: "%+.2f/day", delta),
                required: String(format: ">= %.1f/day", ObservationConstants.trendMinDelta),
                passed: delta >= ObservationConstants.trendMinDelta
            ),
        ]
        return ObservationCandidate(
            kind: .momentum,
            conclusion: window.isEmpty ? nil : .momentumRising,
            gates: gates,
            evidenceCount: olderCount + recentCount,
            topShare: nil
        )
    }

    // MARK: - List return (event)

    static func listReturnCandidate(
        at snapshot: CivilDay, prepared: Prepared
    ) -> (candidate: ObservationCandidate, firedOn: CivilDay?) {
        // The event window: a return surfaces within the week, then expires.
        let eventHorizon = snapshot.advanced(by: -6)

        struct ReturnEvent {
            let listId: String
            let firedOn: CivilDay
            let quietDays: Int
            let history: Int
            let quietSpellClean: Bool
        }

        var best: ReturnEvent?
        for listId in prepared.knownListIds.sorted() {
            let completions = prepared.records
                .filter { $0.stat.listId == listId }
                .map(\.day)
                .sorted()
            guard completions.count >= 2 else { continue }
            for (previous, next) in zip(completions, completions.dropFirst()) {
                let gap = next.dayNumber - previous.dayNumber
                guard gap >= ObservationConstants.returnQuietDays,
                      next >= eventHorizon, next <= snapshot
                else { continue }
                // Real prior history: the list mattered before it went quiet.
                let history = completions.filter { $0 <= previous }.count
                // Absence during vacation/lapse (or before the log can
                // attest) wasn't behavior - the event stays silent.
                var clean = true
                var day = previous.advanced(by: 1)
                while day < next {
                    if prepared.eligibility(of: day) != .eligible {
                        clean = false
                        break
                    }
                    day = day.advanced(by: 1)
                }
                let event = ReturnEvent(
                    listId: listId, firedOn: next, quietDays: gap,
                    history: history, quietSpellClean: clean
                )
                // Latest return wins; listId order breaks same-day ties.
                if best == nil || event.firedOn > best!.firedOn {
                    best = event
                }
            }
        }

        guard let best else {
            return (ObservationCandidate(
                kind: .listReturn,
                conclusion: nil,
                gates: [ObservationGateCheck(
                    name: "return event",
                    achieved: "no completion after a quiet spell this week",
                    required: ">= \(ObservationConstants.returnQuietDays) quiet days, then a completion",
                    passed: false
                )],
                evidenceCount: 0,
                topShare: nil
            ), nil)
        }

        let gates = [
            ObservationGateCheck(
                name: "quiet spell",
                achieved: "\(best.quietDays) days",
                required: ">= \(ObservationConstants.returnQuietDays) days",
                passed: true
            ),
            gate("prior history", count: best.history, atLeast: ObservationConstants.returnHistoryMin),
            ObservationGateCheck(
                name: "quiet spell clean",
                achieved: best.quietSpellClean ? "no vacation/lapse/unknown days" : "overlaps vacation, lapse, or pre-log days",
                required: "absence must be behavior",
                passed: best.quietSpellClean
            ),
        ]
        return (ObservationCandidate(
            kind: .listReturn,
            conclusion: .listReturn(listId: best.listId),
            gates: gates,
            evidenceCount: best.history,
            topShare: nil
        ), best.firedOn)
    }

    // MARK: - Deterministic hysteresis

    /// Replays daily gate evaluations over the fixed depth, folding the
    /// switch/retire state machine forward from an empty seed. A pure
    /// function over synced records + the synced interval log: every
    /// device computes the same incumbent, no stability state stored.
    static func replay(
        _ kind: ObservationKind, endingAt today: CivilDay, prepared: Prepared
    ) -> ObservationReplayTimeline {
        var incumbent: ObservationConclusion?
        var stableSince: CivilDay?
        var failStreak = 0
        // The current run of consecutive days one conclusion has passed.
        var streak: (conclusion: ObservationConclusion, start: CivilDay, length: Int)?
        var days: [ObservationReplayDay] = []

        let start = today.advanced(by: -(ObservationConstants.replayDays - 1))
        var day = start
        while day <= today {
            let candidate = traitCandidate(kind, at: day, prepared: prepared)
            let passing = candidate.passesAllGates ? candidate.conclusion : nil

            if let passing {
                if let current = streak, current.conclusion == passing {
                    streak = (passing, current.start, current.length + 1)
                } else {
                    streak = (passing, day, 1)
                }
            } else {
                streak = nil
            }

            if let current = incumbent {
                if passing == current {
                    failStreak = 0
                } else {
                    failStreak += 1
                    if failStreak >= ObservationConstants.stickyDays {
                        if let challenger = streak,
                           challenger.conclusion != current,
                           challenger.length >= ObservationConstants.stickyDays {
                            // Switch: the challenger passed throughout the
                            // incumbent's whole fail streak.
                            incumbent = challenger.conclusion
                            stableSince = challenger.start
                        } else {
                            // Retire: silence beats a stale conclusion.
                            incumbent = nil
                            stableSince = nil
                        }
                        failStreak = 0
                    }
                }
            } else if let current = streak, current.length >= ObservationConstants.stickyDays {
                incumbent = current.conclusion
                stableSince = current.start
                failStreak = 0
            }

            days.append(ObservationReplayDay(
                day: day.dateString,
                passing: passing,
                incumbent: incumbent,
                incumbentFailStreak: failStreak
            ))
            day = day.advanced(by: 1)
        }

        return ObservationReplayTimeline(
            kind: kind,
            days: days,
            incumbent: incumbent,
            stableSince: stableSince?.dateString
        )
    }

    // MARK: - Gate helpers

    private static func gate(_ name: String, count: Int, atLeast floor: Int) -> ObservationGateCheck {
        ObservationGateCheck(
            name: name, achieved: "\(count)", required: ">= \(floor)", passed: count >= floor
        )
    }

    private static func gate(_ name: String, share: Double, atLeast floor: Double) -> ObservationGateCheck {
        ObservationGateCheck(
            name: name,
            achieved: String(format: "%.0f%%", share * 100),
            required: String(format: ">= %.0f%%", floor * 100),
            passed: share >= floor
        )
    }

    /// An unopposed top passes; a real tie is exactly the "when unsure"
    /// case and fails.
    private static func marginGate(top: Int, runnerUp: Int) -> ObservationGateCheck {
        let passed = top > 0
            && (runnerUp == 0 || Double(top) >= ObservationConstants.marginRatio * Double(runnerUp))
        return ObservationGateCheck(
            name: "runner-up margin",
            achieved: "\(top) vs \(runnerUp)",
            required: String(format: ">= %.1fx runner-up", ObservationConstants.marginRatio),
            passed: passed
        )
    }

    private static func median(of sorted: [TimeInterval]) -> TimeInterval? {
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Nearest-rank p75.
    private static func percentile75(of sorted: [TimeInterval]) -> TimeInterval? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((0.75 * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(rank - 1, 0)]
    }

    private static func hoursText(_ interval: TimeInterval?) -> String {
        guard let interval else { return "-" }
        return String(format: "%.1fh", interval / 3600)
    }
}
