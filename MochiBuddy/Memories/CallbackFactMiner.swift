//
//  CallbackFactMiner.swift
//  MochiBuddy
//
//  Pure fact mining (Personal Layer, Feature 2): completion stats and
//  synced streak fields in, provable positive memories out. Facts draw
//  from the same 132-day fetch Feature 4's replay already makes - no new
//  query. Everything is a pure function of its inputs with explicit
//  evaluation day; no clock reads, no zone surprises (records carry
//  their own completion-local context, exactly like the observation
//  engine).
//
//  The guilt-ledger line: only wins are facts here. A day that wasn't a
//  best day, an episode that wasn't a dig-out - those are silence.
//

import Foundation

struct CallbackMinerInputs {
    var records: [CompletedTaskStat] = []
    var adoptedOn: String?
    var streakCount = 0
    var bestStreakCount = 0
    /// Date-only, stamped atomically with the record; nil for legacy
    /// records (never guessed).
    var bestStreakAchievedOn: String?
    /// The last streak-active civil day, under the caller's calendar.
    var lastActiveDay: CivilDay?
}

enum CallbackFactMiner {

    /// Every type's evaluation for one civil day - floors, ages, and the
    /// relationship gate applied. Selection-level gates live in the
    /// planner.
    static func evaluate(_ inputs: CallbackMinerInputs, on day: CivilDay) -> [CallbackEvaluation] {
        // Activation: no day-3 nostalgia. Applies to every type at once.
        guard let adoptedOn = inputs.adoptedOn,
              let adopted = CivilDay(adoptedOn),
              day.dayNumber - adopted.dayNumber >= CallbackConstants.minAgeDays
        else {
            return CallbackType.allCases.map {
                CallbackEvaluation(type: $0, fact: nil, blocked: .relationshipAge)
            }
        }

        let days = completionDays(inputs.records)
        return [
            dateEcho(days: days, on: day),
            recovery(inputs.records, on: day),
            bestDay(days: days, on: day),
            streakEra(inputs, on: day),
        ]
    }

    /// Qualifying facts only, selection-priority ordered - the planner's
    /// candidate list.
    static func facts(_ inputs: CallbackMinerInputs, on day: CivilDay) -> [CallbackFact] {
        evaluate(inputs, on: day)
            .compactMap(\.fact)
            .sorted { $0.type.priority < $1.type.priority }
    }

    // MARK: - Per-day completion identity counting

    struct DayStats: Equatable {
        let day: CivilDay
        let count: Int
        let distinctKeys: Int
    }

    /// Completions bucketed by their own completion-local civil day, with
    /// the distinct-identity count the diversity floors gate on (one
    /// habit is one identity).
    private static func completionDays(_ records: [CompletedTaskStat]) -> [DayStats] {
        var perDay: [CivilDay: (count: Int, keys: Set<String>)] = [:]
        for record in records {
            guard let day = CivilDay(record.completedLocalDate) else { continue }
            var entry = perDay[day] ?? (0, [])
            entry.count += 1
            entry.keys.insert(record.seriesId ?? record.taskId)
            perDay[day] = entry
        }
        return perDay
            .map { DayStats(day: $0.key, count: $0.value.count, distinctKeys: $0.value.keys.count) }
            .sorted { $0.day < $1.day }
    }

    private static func clearsBestDayFloor(_ stats: DayStats) -> Bool {
        stats.count >= CallbackConstants.bestDayMin
            && stats.distinctKeys >= CallbackConstants.bestDayMin
    }

    // MARK: - Best day

    private static func bestDay(days: [DayStats], on day: CivilDay) -> CallbackEvaluation {
        let qualifying = days.filter { $0.day < day && clearsBestDayFloor($0) }
        guard !qualifying.isEmpty else {
            return CallbackEvaluation(
                type: .bestDay, fact: nil,
                blocked: days.contains(where: { $0.day < day }) ? .evidence : .noFact
            )
        }
        let maxCount = qualifying.map(\.count).max() ?? 0
        let standouts = qualifying.filter { $0.count == maxCount }
        // Deterministic tie rule: the latest qualifying day wins; a tied
        // max is "one of your biggest days", never a false superlative.
        guard let standout = standouts.max(by: { $0.day < $1.day }) else {
            return CallbackEvaluation(type: .bestDay, fact: nil, blocked: .noFact)
        }
        // Fact age: on day 21, yesterday's five completions are not yet a
        // memory.
        guard day.dayNumber - standout.day.dayNumber >= CallbackConstants.factAgeDays else {
            return CallbackEvaluation(type: .bestDay, fact: nil, blocked: .factAge)
        }
        return CallbackEvaluation(
            type: .bestDay,
            fact: CallbackFact(
                type: .bestDay,
                factId: CallbackFactID.completionDay(standout.day),
                sourceDay: standout.day,
                count: standout.count,
                tied: standouts.count > 1
            ),
            blocked: nil
        )
    }

    // MARK: - Recovery

    struct RecoveryEpisode: Equatable {
        let windowStart: CivilDay
        let lastClearDay: CivilDay
        let contributingKeys: [String]
    }

    /// Genuine dig-outs: >= 3 overdue tasks from distinct tasks/series
    /// cleared inside 48h, with at least one >= 24h overdue. Lateness is
    /// computed against the app's one overdue rule, in each record's own
    /// completion zone.
    static func recoveryEpisodes(_ records: [CompletedTaskStat]) -> [RecoveryEpisode] {
        struct Clear {
            let completedAt: Date
            let day: CivilDay
            let key: String
            let lateness: TimeInterval
        }
        let clears: [Clear] = records.compactMap { record in
            guard let day = CivilDay(record.completedLocalDate),
                  let lateness = lateness(of: record), lateness > 0
            else { return nil }
            return Clear(
                completedAt: record.completedAt,
                day: day,
                key: record.seriesId ?? record.taskId,
                lateness: lateness
            )
        }.sorted { $0.completedAt < $1.completedAt }

        var episodes: [RecoveryEpisode] = []
        var index = 0
        while index < clears.count {
            let windowEnd = clears[index].completedAt
                .addingTimeInterval(CallbackConstants.recoveryWindowHours * 3600)
            let window = clears[index...].prefix { $0.completedAt <= windowEnd }
            let keys = Set(window.map(\.key))
            let deepEnough = window.contains {
                $0.lateness >= CallbackConstants.recoveryMinOverdueHours * 3600
            }
            if keys.count >= CallbackConstants.recoveryMinClears, deepEnough {
                episodes.append(RecoveryEpisode(
                    windowStart: clears[index].day,
                    lastClearDay: window.map(\.day).max() ?? clears[index].day,
                    contributingKeys: Array(keys)
                ))
                // Greedy, non-overlapping: an episode is one true story,
                // not a sliding smear of near-duplicates.
                index += window.count
            } else {
                index += 1
            }
        }
        return episodes
    }

    /// Seconds past the overdue boundary; nil when undated or on time.
    /// Timed tasks flip at dueAt; date-only tasks flip at the end of the
    /// due day, evaluated in the record's own completion zone.
    static func lateness(of record: CompletedTaskStat) -> TimeInterval? {
        guard let dueAt = record.dueAt else { return nil }
        let boundary: Date
        if record.hasTime {
            boundary = dueAt
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: record.completionTimeZone)
                ?? TimeZone(identifier: "UTC")!
            boundary = calendar.startOfDay(for: dueAt).addingTimeInterval(86_400)
        }
        let late = record.completedAt.timeIntervalSince(boundary)
        return late > 0 ? late : nil
    }

    private static func recovery(_ records: [CompletedTaskStat], on day: CivilDay) -> CallbackEvaluation {
        let episodes = recoveryEpisodes(records).filter { $0.lastClearDay < day }
        guard let latest = episodes.max(by: { $0.lastClearDay < $1.lastClearDay }) else {
            let anyOverdueClear = records.contains { (lateness(of: $0) ?? 0) > 0 }
            return CallbackEvaluation(
                type: .recovery, fact: nil,
                blocked: anyOverdueClear ? .evidence : .noFact
            )
        }
        guard day.dayNumber - latest.lastClearDay.dayNumber >= CallbackConstants.factAgeDays else {
            return CallbackEvaluation(type: .recovery, fact: nil, blocked: .factAge)
        }
        return CallbackEvaluation(
            type: .recovery,
            fact: CallbackFact(
                type: .recovery,
                factId: CallbackFactID.recovery(
                    contributingKeys: latest.contributingKeys, windowStart: latest.windowStart
                ),
                sourceDay: latest.lastClearDay
            ),
            blocked: nil
        )
    }

    // MARK: - Streak era

    private static func streakEra(_ inputs: CallbackMinerInputs, on day: CivilDay) -> CallbackEvaluation {
        guard inputs.bestStreakCount >= CallbackConstants.streakEraMin else {
            return CallbackEvaluation(
                type: .streakEra, fact: nil,
                blocked: inputs.bestStreakCount > 0 ? .evidence : .noFact
            )
        }

        let achievedDay = inputs.bestStreakAchievedOn.flatMap { CivilDay($0) }

        // The record belongs to the currently active streak when counts
        // match and the run is alive at the evaluation day.
        let runAlive = inputs.lastActiveDay.map { day.dayNumber - $0.dayNumber <= 1 } ?? false
        let recordIsActiveRun = runAlive && inputs.bestStreakCount == inputs.streakCount

        if recordIsActiveRun, let lastActive = inputs.lastActiveDay {
            // Day 30 must not be congratulated and then "remembered" a
            // week later: quiet while the run's latest milestone
            // celebration is fresh. The milestone's achievement day is
            // derivable - the streak advances one count per active day.
            let milestones = (1...inputs.streakCount).filter { StreakMilestones.isMilestone($0) }
            if let latest = milestones.max() {
                let celebratedDay = lastActive.advanced(by: -(inputs.streakCount - latest))
                if day.dayNumber - celebratedDay.dayNumber < CallbackConstants.streakQuietDays {
                    return CallbackEvaluation(type: .streakEra, fact: nil, blocked: .evidence)
                }
            }
        }

        // Fact age: a record achieved this week is not yet an era - unless
        // the run has since ended, which closes the book on it.
        if recordIsActiveRun, let achievedDay,
           day.dayNumber - achievedDay.dayNumber < CallbackConstants.factAgeDays {
            return CallbackEvaluation(type: .streakEra, fact: nil, blocked: .factAge)
        }

        return CallbackEvaluation(
            type: .streakEra,
            fact: CallbackFact(
                type: .streakEra,
                factId: CallbackFactID.streakRecord(
                    count: inputs.bestStreakCount, achievedOn: inputs.bestStreakAchievedOn
                ),
                sourceDay: achievedDay ?? day,
                streakCount: inputs.bestStreakCount,
                eraDated: achievedDay != nil
            ),
            blocked: nil
        )
    }

    // MARK: - Date echo

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// The day exactly `months` whole months before, platform-clamped
    /// (Mar 31 minus one month is Feb 28/29).
    static func monthsBack(_ months: Int, from day: CivilDay) -> CivilDay? {
        let anchor = Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
        guard let shifted = utcCalendar.date(byAdding: .month, value: -months, to: anchor) else {
            return nil
        }
        return CivilDay(of: shifted, in: utcCalendar)
    }

    private static func dateEcho(days: [DayStats], on day: CivilDay) -> CallbackEvaluation {
        // The horizon caps how far an echo can reach; five months is
        // already past the 132-day fetch.
        var nearMiss = false
        for months in 1...5 {
            guard let echoDay = monthsBack(months, from: day) else { continue }
            guard let stats = days.first(where: { $0.day == echoDay }) else { continue }
            guard clearsBestDayFloor(stats) else {
                nearMiss = true
                continue
            }
            // Most recent qualifying occurrence wins (smallest k). Echo is
            // date-bound: no fact-age floor, and it expires silently at
            // the end of its date.
            return CallbackEvaluation(
                type: .dateEcho,
                fact: CallbackFact(
                    type: .dateEcho,
                    factId: CallbackFactID.completionDay(echoDay),
                    sourceDay: echoDay,
                    count: stats.count,
                    monthsBack: months
                ),
                blocked: nil
            )
        }
        return CallbackEvaluation(
            type: .dateEcho, fact: nil, blocked: nearMiss ? .evidence : .noFact
        )
    }
}
