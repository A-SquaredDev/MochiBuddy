//
//  SuggestionEngine.swift
//  MochiBuddy
//
//  The pure suggestion pipeline (Personal Layer, Feature 5): scoped
//  distributions in, at most one time proposal out. Qualification runs on
//  RAW day-capped counts (weights never help qualification); the
//  reschedule bias shapes the peak of an already-qualified distribution;
//  the proposal is friendly-rounded and every guardrail evaluates the
//  rounded time. When unsure - bimodal, thin, too close to now, inside
//  bedtime - the answer is silence, never a clamped or shifted time.
//
//  Everything is a pure function of its inputs: distributions, task
//  snapshot, constants, and caller-computed today/now-minute. No clock
//  reads, no zone reads - same inputs, same chip, on every device.
//

import Foundation

enum SuggestionEngine {

    /// The task fields an evaluation reads, frozen by the caller.
    struct TaskSnapshot: Equatable {
        let listId: String?
        let isRecurring: Bool
        let hasTime: Bool
        /// Minute-of-day of the due time, when `hasTime`.
        let scheduledMinute: Int?
        /// Civil date of the due date in the caller's zone; nil = no date.
        let dueDay: String?
        let isAppleSource: Bool
    }

    /// Everything else an evaluation reads, assembled once per session.
    struct Context: Equatable {
        /// Scope .series - present only when the task has a series identity.
        let series: DistributionResult?
        /// Scope .list - present only when the task has a list.
        let list: DistributionResult?
        /// Scope .globalFallback - always present.
        let global: DistributionResult
        let bedtime: BedtimeWindow
        let isLapsed: Bool
        /// Caller-computed civil date and local minute at evaluation.
        let today: String
        let nowMinute: Int
    }

    // MARK: - Entry points

    /// New-time trigger: date set, no time chosen. Preconditions are the
    /// caller's contract; when they don't hold the evaluation is empty
    /// (proposal nil, blocked nil) - nothing held, nothing to report.
    static func evaluateNewTime(
        task: TaskSnapshot, context: Context, dismissedAt: Int?
    ) -> SuggestionEvaluation {
        guard task.dueDay != nil, !task.hasTime else {
            return SuggestionEvaluation(trigger: .newTime, proposal: nil, blocked: nil, gates: [])
        }
        if context.isLapsed {
            return blocked(.newTime, .lapsed)
        }
        if task.isAppleSource {
            return blocked(.newTime, .apple)
        }

        // Highest QUALIFYING scope: series, else list, else global - a
        // scope wins only by passing all of its own gates. The blocked
        // reason, when nothing qualifies, is the widest scope's story
        // (global is the last resort; its failure is the true silence).
        var attempts: [(tier: SuggestionScopeTier, result: ScopeResult)] = []
        if let series = context.series {
            attempts.append((.series, qualify(series, floors: .series)))
        }
        if let list = context.list, task.listId != nil {
            attempts.append((.list, qualify(list, floors: .general, listGuards: true)))
        }
        attempts.append((.global, qualify(context.global, floors: .general)))

        let gates = attempts.flatMap(\.result.gates)
        guard let winner = attempts.first(where: { $0.result.peak != nil }),
              let peak = winner.result.peak
        else {
            let reason = attempts.last?.result.firstFailure ?? .evidence
            return SuggestionEvaluation(
                trigger: .newTime, proposal: nil, blocked: reason, gates: gates
            )
        }

        let proposal = SuggestionProposal(
            trigger: .newTime,
            tier: winner.tier,
            listId: winner.tier == .list ? task.listId : nil,
            peakMinute: peak.peakMinute,
            displayedMinute: friendlyRounded(peak.peakMinute),
            evidenceCount: peak.evidenceCount,
            isRecurring: task.isRecurring
        )
        return guarded(proposal, task: task, context: context, dismissedAt: dismissedAt, gates: gates)
    }

    /// Re-time trigger: a recurring Mochi series with a due time whose
    /// completions persistently land far from it. Series scope only -
    /// there is no future series to change on a one-off, and no series is
    /// ever inferred from titles.
    static func evaluateReTime(
        task: TaskSnapshot, context: Context, dismissedAt: Int?
    ) -> SuggestionEvaluation {
        guard task.isRecurring, task.hasTime, let scheduledMinute = task.scheduledMinute,
              let series = context.series
        else {
            return SuggestionEvaluation(trigger: .reTime, proposal: nil, blocked: nil, gates: [])
        }
        if context.isLapsed {
            return blocked(.reTime, .lapsed)
        }
        if task.isAppleSource {
            return blocked(.reTime, .apple)
        }

        let result = qualify(series, floors: .series)
        guard let peak = result.peak else {
            return SuggestionEvaluation(
                trigger: .reTime, proposal: nil,
                blocked: result.firstFailure ?? .evidence, gates: result.gates
            )
        }

        // Mismatch is measured on the UNROUNDED peak; only the proposal
        // is rounded.
        let mismatch = circularDistance(peak.peakMinute, scheduledMinute)
        let required = SuggestionConstants.retimeMismatchHours * 60
        let mismatchGate = ObservationGateCheck(
            name: "schedule mismatch",
            achieved: "\(mismatch)m",
            required: ">= \(required)m",
            passed: mismatch >= required
        )
        let gates = result.gates + [mismatchGate]
        guard mismatchGate.passed else {
            return SuggestionEvaluation(
                trigger: .reTime, proposal: nil, blocked: .mismatch, gates: gates
            )
        }

        let proposal = SuggestionProposal(
            trigger: .reTime,
            tier: .series,
            listId: nil,
            peakMinute: peak.peakMinute,
            displayedMinute: friendlyRounded(peak.peakMinute),
            evidenceCount: peak.evidenceCount,
            isRecurring: true
        )
        return guarded(proposal, task: task, context: context, dismissedAt: dismissedAt, gates: gates)
    }

    // MARK: - Guardrails (never clamp, never fabricate)

    private static func guarded(
        _ proposal: SuggestionProposal,
        task: TaskSnapshot,
        context: Context,
        dismissedAt: Int?,
        gates: [ObservationGateCheck]
    ) -> SuggestionEvaluation {
        // All guardrails evaluate the ROUNDED time.
        let displayed = proposal.displayedMinute
        if context.bedtime.containsMinute(displayed) {
            return SuggestionEvaluation(
                trigger: proposal.trigger, proposal: nil, blocked: .bedtime, gates: gates
            )
        }
        // Today-due: a 10:00 chip at 9:58 is practically useless - it is
        // silenced, never moved later. Linear comparison on purpose: a
        // displayed time earlier than now already passed today.
        if task.dueDay == context.today,
           displayed < context.nowMinute + SuggestionConstants.minLeadMin {
            return SuggestionEvaluation(
                trigger: proposal.trigger, proposal: nil, blocked: .leadTime, gates: gates
            )
        }
        // Once-until-changed: hidden while the DISPLAYED proposal sits
        // within the re-arm distance of the dismissed one.
        if let dismissedAt,
           circularDistance(displayed, dismissedAt) < SuggestionConstants.dismissRearmMin {
            return SuggestionEvaluation(
                trigger: proposal.trigger, proposal: nil, blocked: .dismissed, gates: gates
            )
        }
        return SuggestionEvaluation(
            trigger: proposal.trigger, proposal: proposal, blocked: nil, gates: gates
        )
    }

    private static func blocked(
        _ trigger: SuggestionTrigger, _ reason: SuggestionBlockedReason
    ) -> SuggestionEvaluation {
        SuggestionEvaluation(trigger: trigger, proposal: nil, blocked: reason, gates: [])
    }

    // MARK: - Scope qualification (raw day-capped counts)

    enum Floors {
        case general
        case series

        var evidence: Int {
            switch self {
            case .general: SuggestionConstants.minEvidence
            case .series: SuggestionConstants.seriesMin
            }
        }
        var dates: Int {
            switch self {
            case .general: SuggestionConstants.minDates
            case .series: SuggestionConstants.seriesDates
            }
        }
    }

    struct WindowPeak: Equatable {
        let center: Int
        let share: Double
        let runnerUpShare: Double
        /// Weighted circular center of the primary window's entries -
        /// the unrounded peak.
        let peakMinute: Int
        let evidenceCount: Int
    }

    struct ScopeResult: Equatable {
        let peak: WindowPeak?
        let gates: [ObservationGateCheck]
        let firstFailure: SuggestionBlockedReason?
    }

    /// The full gate table for one scope. Weights are absent everywhere
    /// here except the final peak-minute computation - qualification is
    /// raw counts, always.
    static func qualify(
        _ distribution: DistributionResult, floors: Floors, listGuards: Bool = false
    ) -> ScopeResult {
        var gates: [ObservationGateCheck] = []
        var failure: SuggestionBlockedReason?

        func gate(
            _ name: String, achieved: String, required: String, passed: Bool,
            reason: SuggestionBlockedReason
        ) -> Bool {
            gates.append(ObservationGateCheck(
                name: name, achieved: achieved, required: required, passed: passed
            ))
            if !passed, failure == nil { failure = reason }
            return passed
        }

        let entries = distribution.entries
        let total = entries.count

        let evidenceOK = gate(
            "evidence floor", achieved: "\(total)", required: ">= \(floors.evidence)",
            passed: total >= floors.evidence, reason: .evidence
        )
        let dates = distribution.distinctDates
        let datesOK = gate(
            "distinct dates", achieved: "\(dates)", required: ">= \(floors.dates)",
            passed: dates >= floors.dates, reason: .evidence
        )

        if listGuards {
            var perIdentity: [String: Int] = [:]
            for entry in entries {
                perIdentity[entry.identity, default: 0] += 1
            }
            let identities = perIdentity.count
            let topIdentityShare = total > 0
                ? Double(perIdentity.values.max() ?? 0) / Double(total)
                : 0
            // Not in the coarse reason vocabulary on purpose: a failed
            // list guard falls through to global, so it can never be the
            // final blocked reason.
            _ = gate(
                "list identities", achieved: "\(identities)",
                required: ">= \(SuggestionConstants.listMinSeries)",
                passed: identities >= SuggestionConstants.listMinSeries, reason: .evidence
            )
            _ = gate(
                "list concentration",
                achieved: String(format: "%.0f%%", topIdentityShare * 100),
                required: String(format: "<= %.0f%%", SuggestionConstants.listSeriesShare * 100),
                passed: topIdentityShare <= SuggestionConstants.listSeriesShare, reason: .evidence
            )
        }

        guard evidenceOK, datesOK, gates.allSatisfy(\.passed), total > 0 else {
            return ScopeResult(peak: nil, gates: gates, firstFailure: failure)
        }

        // Deterministic window scan: 48 half-hour candidate centers, each
        // window HALF-OPEN [center - w, center + w) in circular minutes so
        // two windows whose centers sit 2w apart are disjoint - a boundary
        // completion counts in exactly one of them, and the runner-up gate
        // compares genuinely non-overlapping patterns. Raw day-capped
        // counts. Primary = max count; ties break to the earliest center
        // (a REAL tie dies at the margin gate anyway).
        let windows = (0..<48).map { index -> (center: Int, count: Int) in
            let center = index * 30
            let count = entries.count { inWindow($0.minute, center: center) }
            return (center, count)
        }
        let primary = windows.max { ($0.count, -$0.center) < ($1.count, -$1.center) }!
        let primaryShare = Double(primary.count) / Double(total)
        let inPrimary = entries.filter { inWindow($0.minute, center: primary.center) }

        // Runner-up: the best window centered >= 3 circular hours away.
        let runnerUp = windows
            .filter { circularDistance($0.center, primary.center) >= 180 }
            .max { ($0.count, -$0.center) < ($1.count, -$1.center) }
        let runnerUpShare = Double(runnerUp?.count ?? 0) / Double(total)

        let shareOK = gate(
            "peak share", achieved: String(format: "%.0f%%", primaryShare * 100),
            required: String(format: ">= %.0f%%", SuggestionConstants.peakShare * 100),
            passed: primaryShare >= SuggestionConstants.peakShare, reason: .peakShare
        )
        let peakDates = Set(inPrimary.map(\.day)).count
        let peakDatesOK = gate(
            "peak dates", achieved: "\(peakDates)",
            required: ">= \(SuggestionConstants.peakDates)",
            passed: peakDates >= SuggestionConstants.peakDates, reason: .peakDates
        )
        let margin = primaryShare - runnerUpShare
        let marginOK = gate(
            "runner-up margin", achieved: String(format: "%.2f", margin),
            required: String(format: ">= %.2f", SuggestionConstants.runnerUpMargin),
            passed: margin >= SuggestionConstants.runnerUpMargin, reason: .runnerUp
        )

        guard shareOK, peakDatesOK, marginOK else {
            return ScopeResult(peak: nil, gates: gates, firstFailure: failure)
        }

        // Weights shape the peak of the ALREADY-QUALIFIED distribution:
        // a completion the user kept moving is extra-informative about
        // when things actually happen. nil = unknown, weight 1 - never
        // "known unmoved".
        let weighted = inPrimary.map { entry -> (minute: Int, weight: Double) in
            let bumps = entry.rescheduleCount.map { Double(Swift.min(Swift.max($0, 0), 3)) } ?? 0
            return (entry.minute, 1 + bumps * SuggestionConstants.rescheduleWeight)
        }
        let peakMinute = weightedCircularCenter(weighted) ?? primary.center

        return ScopeResult(
            peak: WindowPeak(
                center: primary.center,
                share: primaryShare,
                runnerUpShare: runnerUpShare,
                peakMinute: peakMinute,
                evidenceCount: total
            ),
            gates: gates,
            firstFailure: nil
        )
    }

    // MARK: - Circular math

    /// Half-open circular window membership: minute in
    /// [center - peakWindowMin, center + peakWindowMin).
    private static func inWindow(_ minute: Int, center: Int) -> Bool {
        let w = SuggestionConstants.peakWindowMin
        return (((minute - center + w) % 1440) + 1440) % 1440 < 2 * w
    }

    /// Circular distance between two minutes-of-day, 0...720.
    static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let diff = abs(a - b) % 1440
        return Swift.min(diff, 1440 - diff)
    }

    /// Weighted circular center; nil for an empty or evenly-opposed set.
    static func weightedCircularCenter(_ values: [(minute: Int, weight: Double)]) -> Int? {
        guard !values.isEmpty else { return nil }
        var sinSum = 0.0
        var cosSum = 0.0
        for value in values {
            let angle = Double(value.minute) / 1440 * 2 * .pi
            sinSum += sin(angle) * value.weight
            cosSum += cos(angle) * value.weight
        }
        guard sinSum * sinSum + cosSum * cosSum > 1e-9 else { return nil }
        var angle = atan2(sinSum, cosSum)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * 1440).rounded()) % 1440
    }

    /// Friendly rounding, pinned: nearest half hour; an exact quarter-hour
    /// tie rounds EARLIER; a round-up that would land on next-day 00:00
    /// falls back to 23:30 - rounding never crosses the task's date
    /// boundary, and a guardrail conflict silences rather than shifts.
    static func friendlyRounded(_ minute: Int) -> Int {
        let clamped = ((minute % 1440) + 1440) % 1440
        let lower = (clamped / 30) * 30
        let upper = lower + 30
        let chosen = (clamped - lower) > (upper - clamped) ? upper : lower
        return chosen >= 1440 ? 1410 : chosen
    }
}

extension BedtimeWindow {
    /// Minute-of-day membership - the suggestion guardrail's form of the
    /// same wrap-aware window `contains(_:)` evaluates for instants.
    func containsMinute(_ minute: Int) -> Bool {
        guard startMinutes != endMinutes else { return false }
        return startMinutes < endMinutes
            ? minute >= startMinutes && minute < endMinutes
            : minute >= startMinutes || minute < endMinutes
    }
}
