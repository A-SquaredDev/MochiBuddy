//
//  NotificationPlanner.swift
//  MochiBuddy
//
//  The pure heart of the scheduler: snapshot + prefs in, the desired
//  pending set out. No UN* types, no clock, no I/O - everything here is
//  deterministic and unit-testable. The center adapter diffs this plan
//  against what iOS actually has pending.
//
//  Doc rules encoded here (Notifications → Scheduling model + Cadence):
//  predict pessimistically off the falling forecast; escalate at the
//  floor with the taper brake; quiet-hours fires are dropped, never
//  shifted; suppressions (shh, vacation, lapsed) compose and only
//  vacation may silence a promise; budget promises → mood → rundowns
//  into the 64 slots with one reserved backstop.
//

import Foundation

struct NotificationPlanInput {
    var snapshot: MoodSnapshot
    var bedtime: BedtimeWindow = .standard
    var prefs: NotificationPrefs = .standard
    var lapsed = false
    /// "Mochi, shh" - mood pings before this instant are dropped.
    var shhUntil: Date? = nil
    /// Completed consecutive days at the floor before capture - the taper
    /// state the orchestrator persists across lays.
    var consecutiveFloorDays = 0
    /// Requested planning horizon (the forecast further caps this at
    /// entitlement expiry for everything except promises).
    var horizon: Date
}

enum NotificationPlanner {

    struct CadenceRule: Equatable {
        var count: Int
        var spacing: TimeInterval
    }

    /// Remote-tunable via RemoteTuning, set once at launch.
    enum Constants {
        /// iOS's pending-notification ceiling - a platform fact, not a knob.
        static let slotCap = 64
        /// Hard global ceiling on mood pings per day, every dial setting.
        static var moodPingsPerDayCeiling = 4
        /// Floor-state taper: day 1 = 4 … day 4+ = 1, indefinitely.
        static var floorTaperBudgets = [4, 3, 2, 1]
        /// The dormant-user safety net repeats on this interval.
        static var backstopInterval: TimeInterval = 7 * 24 * 3600
        /// Per-band daily count + spacing. Bands absent here are silence:
        /// content stays quiet, the happy side is carried by real
        /// celebrations, never by predictions.
        static var cadenceRules: [MoodBand: CadenceRule] = [
            .verySad: CadenceRule(count: 4, spacing: 2 * 3600),
            .anxious: CadenceRule(count: 3, spacing: 3 * 3600),
            .uneasy: CadenceRule(count: 1, spacing: 4 * 3600),
        ]

        static func cadence(for band: MoodBand, level: NudgeLevel) -> (count: Int, spacing: TimeInterval) {
            let rule = cadenceRules[band] ?? CadenceRule(count: 0, spacing: 4 * 3600)
            // "Rarely" caps every band at one gentle ping a day - quieting
            // Mochi must never require the system-level off switch.
            if level == .rarely {
                return (min(rule.count, 1), rule.spacing)
            }
            return (rule.count, rule.spacing)
        }
    }

    /// The full desired pending set, sorted by fire time, within budget.
    static func plan(
        _ input: NotificationPlanInput,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let promises = planPromises(input)

        // Lapsed: the quiet checklist keeps its real reminders,
        // indefinitely, and gets nothing else - the winback IS the app
        // staying useful. No mood, no rundown, no backstop, no guilt.
        guard !input.lapsed else {
            return budget(promises: promises, backstop: [], moodPings: [], rundowns: [])
        }

        let moodPings = planMoodPings(input, calendar: calendar)
        let rundowns = planRundowns(input, calendar: calendar)
        let backstop = planBackstop(input)
        return budget(promises: promises, backstop: backstop, moodPings: moodPings, rundowns: rundowns)
    }

    // MARK: - Promises

    /// One exact reminder per future timed task. Date-only tasks have no
    /// instant to promise; the morning rundown carries them. Vacation is
    /// the ONE suppression allowed to silence a promise (truly silent).
    private static func planPromises(_ input: NotificationPlanInput) -> [PlannedNotification] {
        guard input.prefs.taskReminders else { return [] }
        return input.snapshot.tasks.compactMap { task in
            guard !task.completed, task.hasTime, let dueAt = task.dueAt,
                  dueAt > input.snapshot.capturedAt,
                  !vacationCovers(dueAt, input: input)
            else { return nil }
            return PlannedNotification(
                id: NotificationID.due(taskId: task.id),
                kind: .promise,
                fireAt: dueAt,
                repeats: task.repeatRule != nil,
                taskId: task.id
            )
        }
    }

    // MARK: - Mood pings

    private static func planMoodPings(
        _ input: NotificationPlanInput,
        calendar: Calendar
    ) -> [PlannedNotification] {
        guard input.prefs.moodDips else { return [] }
        let capture = input.snapshot.capturedAt
        let end = MoodForecast.horizonEnd(requested: input.horizon, snapshot: input.snapshot)
        guard end > capture else { return [] }

        let segments = bandSegments(until: end, input: input, calendar: calendar)
        let floorOrdinals = floorDayOrdinals(
            segments: segments, priorDays: input.consecutiveFloorDays, calendar: calendar
        )

        var pings: [PlannedNotification] = []
        var perDayTotal: [Date: Int] = [:]
        var perDayBand: [Date: [MoodBand: Int]] = [:]
        var lastPingAt: Date?

        for segment in segments {
            let (dailyCount, spacing) = Constants.cadence(for: segment.band, level: input.prefs.level)
            guard dailyCount > 0 else { continue }

            // A segment opening at a crossing pings at the crossing (no
            // entry grace). The capture-time segment already had its entry
            // moment in a previous lay, so it starts one spacing out.
            var candidate = segment.start == capture
                ? capture.addingTimeInterval(spacing)
                : segment.start
            if let last = lastPingAt {
                candidate = max(candidate, last.addingTimeInterval(spacing))
            }

            while candidate < segment.end {
                let day = calendar.startOfDay(for: candidate)
                let dayBudget = segment.band == .verySad
                    ? Constants.floorTaperBudgets[
                        min(max(floorOrdinals[day] ?? 1, 1), Constants.floorTaperBudgets.count) - 1
                      ]
                    : dailyCount

                let bandCount = perDayBand[day]?[segment.band] ?? 0
                let allowed = bandCount < min(dayBudget, dailyCount)
                    && (perDayTotal[day] ?? 0) < Constants.moodPingsPerDayCeiling
                    && !(input.prefs.bedtimeSilence && input.bedtime.contains(candidate, calendar: calendar))
                    && (input.shhUntil.map { candidate >= $0 } ?? true)
                    && !moodPingSuppressed(at: candidate, input: input)

                if allowed {
                    pings.append(PlannedNotification(
                        id: NotificationID.mood(band: segment.band, fireAt: candidate),
                        kind: .moodPing,
                        fireAt: candidate,
                        band: segment.band
                    ))
                    perDayTotal[day, default: 0] += 1
                    perDayBand[day, default: [:]][segment.band, default: 0] += 1
                    lastPingAt = candidate
                }
                // Quiet-hours / budget-blocked candidates are dropped, not
                // shifted - the next candidate keeps the normal spacing, so
                // a silent night never dumps its pings at dawn.
                candidate = candidate.addingTimeInterval(spacing)
            }
        }
        return pings
    }

    private struct BandSegment {
        let band: MoodBand
        let start: Date
        let end: Date
    }

    private static func bandSegments(
        until end: Date,
        input: NotificationPlanInput,
        calendar: Calendar
    ) -> [BandSegment] {
        let snapshot = input.snapshot
        let crossings = MoodForecast.bandCrossings(
            until: end, snapshot: snapshot, calendar: calendar
        )
        var segments: [BandSegment] = []
        var band = MoodForecast.band(at: snapshot.capturedAt, snapshot: snapshot, calendar: calendar)
        var start = snapshot.capturedAt
        for crossing in crossings {
            segments.append(BandSegment(band: band, start: start, end: crossing.date))
            band = crossing.to
            start = crossing.date
        }
        segments.append(BandSegment(band: band, start: start, end: end))
        return segments
    }

    /// Which taper day each forecast floor day is: prior consecutive floor
    /// days carry across the lay, then each forecast day containing floor
    /// time increments (the counter is by calendar day of floor entry).
    private static func floorDayOrdinals(
        segments: [BandSegment],
        priorDays: Int,
        calendar: Calendar
    ) -> [Date: Int] {
        var floorDays: [Date] = []
        for segment in segments where segment.band == .verySad {
            var day = calendar.startOfDay(for: segment.start)
            while day < segment.end {
                if !floorDays.contains(day) {
                    floorDays.append(day)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        var ordinals: [Date: Int] = [:]
        for (index, day) in floorDays.sorted().enumerated() {
            ordinals[day] = priorDays + index + 1
        }
        return ordinals
    }

    // MARK: - Rundown

    /// One briefing per morning at wake (the end of the bedtime window),
    /// inside the entitlement-capped horizon, silent on vacation.
    private static func planRundowns(
        _ input: NotificationPlanInput,
        calendar: Calendar
    ) -> [PlannedNotification] {
        guard input.prefs.morningRundown else { return [] }
        let capture = input.snapshot.capturedAt
        let end = MoodForecast.horizonEnd(requested: input.horizon, snapshot: input.snapshot)

        var rundowns: [PlannedNotification] = []
        var day = calendar.startOfDay(for: capture)
        while day < end {
            if let wake = calendar.date(byAdding: .minute, value: input.bedtime.endMinutes, to: day),
               wake > capture, wake < end,
               !vacationCovers(wake, input: input) {
                rundowns.append(PlannedNotification(
                    id: NotificationID.rundown(on: day, calendar: calendar),
                    kind: .rundown,
                    fireAt: wake
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return rundowns
    }

    // MARK: - Backstop

    /// The repeating safety net so a dormant user past the horizon still
    /// hears from Mochi. Suppressed while vacation holds.
    private static func planBackstop(_ input: NotificationPlanInput) -> [PlannedNotification] {
        guard input.prefs.moodDips else { return [] }
        let fireAt = input.snapshot.capturedAt.addingTimeInterval(Constants.backstopInterval)
        guard !moodPingSuppressed(at: fireAt, input: input) else { return [] }
        return [PlannedNotification(
            id: NotificationID.backstop, kind: .backstop, fireAt: fireAt, repeats: true
        )]
    }

    // MARK: - Budget

    /// Priority over the 64 slots: promises by nearest due, the reserved
    /// backstop, mood pings, then rundowns. Under promise pressure mood
    /// pings degrade to zero (the widget carries) - a reminder is never
    /// the thing dropped.
    private static func budget(
        promises: [PlannedNotification],
        backstop: [PlannedNotification],
        moodPings: [PlannedNotification],
        rundowns: [PlannedNotification]
    ) -> [PlannedNotification] {
        var slots = Constants.slotCap - backstop.count
        var out: [PlannedNotification] = []
        for group in [promises, moodPings, rundowns] {
            let take = min(slots, group.count)
            out += group.sorted { $0.fireAt < $1.fireAt }.prefix(take)
            slots -= take
        }
        out += backstop
        return out.sorted { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }
    }

    private static func vacationCovers(_ t: Date, input: NotificationPlanInput) -> Bool {
        VacationSchedule.isActive(
            mode: input.snapshot.vacationMode,
            startedAt: input.snapshot.vacationStartedAt,
            resumeAt: input.snapshot.vacationResumeAt,
            at: t
        )
    }

    /// Mood pings also stay quiet through the grace window right after a
    /// vacation ends - the wake must be gentle, and the grace buffer that
    /// softens it only exists once the app opens (which re-lays anyway).
    private static func moodPingSuppressed(at t: Date, input: NotificationPlanInput) -> Bool {
        if vacationCovers(t, input: input) { return true }
        guard input.snapshot.vacationMode,
              let end = VacationSchedule.effectiveEnd(
                  startedAt: input.snapshot.vacationStartedAt,
                  resumeAt: input.snapshot.vacationResumeAt
              )
        else { return false }
        return t < end.addingTimeInterval(VacationConstants.graceDecay)
    }
}
