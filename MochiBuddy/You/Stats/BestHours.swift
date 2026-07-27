//
//  BestHours.swift
//  MochiBuddy
//
//  Pure derivations for the "Your best hours" and "Day by day" cards
//  (best-hours-implementation-guide.md). Everything reads the local
//  completion context each CompletedTaskStat carries - the zone where
//  the completion actually happened, never the device's current one.
//
//  Recurring completions are EXCLUDED throughout (D2): a Monday 8am
//  standing chore must not own the peak forever. Deliberately opposite
//  to the Effort total, which is about time spent, not habit shape.
//

import Foundation

/// D5/C4 evidence floors, Remote Config tunable (RemoteTuning).
enum BestHoursConstants {
    /// Day-capped completions required for a weekday row's capsule.
    static var rowMin = 5
    /// Distinct dates required for a weekday row's capsule.
    static var rowDates = 3
    /// Completions required inside a qualifying secondary window.
    static var secondWindMin = 5
    /// Distinct dates required inside a qualifying secondary window.
    static var secondWindDates = 3
    /// The secondary window's share must be at least this fraction of the
    /// peak's. A code constant, deliberately not a Remote Config key, to
    /// hold the console at four new keys (guide §7).
    static let secondWindShareRatio = 0.5
}

enum BestHours {

    /// The chart axis runs 5a to 5a (D3) - `TimeOfDayBand` already defines
    /// the day as starting at 05:00, and a 2am completion should read as
    /// "late", not be clipped off the left edge.
    static let axisOriginMinute = 300

    /// One non-recurring completion, in its own zone.
    struct Entry: Equatable {
        /// Minutes since local midnight, 0...1439.
        let localMinute: Int
        /// The civil day the completion happened in, in its own zone.
        let day: CivilDay
    }

    /// The D2 filter plus local-context extraction.
    static func entries(stats: [CompletedTaskStat]) -> [Entry] {
        stats.compactMap { stat in
            guard !stat.isRecurring, let day = CivilDay(stat.completedLocalDate) else {
                return nil
            }
            return Entry(localMinute: stat.completedLocalMinute, day: day)
        }
    }

    /// Minutes past the 5a axis origin, 0..<1440.
    static func axisMinute(_ localMinute: Int) -> Int {
        (localMinute - axisOriginMinute + 1440) % 1440
    }

    // MARK: - Card 1 · hourly histogram

    struct Histogram: Equatable {
        /// 24 hourly counts; index 0 is the 5a bucket.
        let buckets: [Int]
        /// Start bucket of the best 3-hour run; nil with no data.
        let peakStart: Int?
        /// The peak window's share of all completions, 0...1.
        let inWindowShare: Double
        /// Start bucket of a secondary window that cleared the C4 floor;
        /// nil means Mochi has no second wind worth narrating.
        let secondaryStart: Int?

        var total: Int { buckets.reduce(0, +) }
    }

    static func histogram(entries: [Entry]) -> Histogram {
        var buckets = [Int](repeating: 0, count: 24)
        for entry in entries {
            buckets[axisMinute(entry.localMinute) / 60] += 1
        }
        let total = buckets.reduce(0, +)
        guard total > 0 else {
            return Histogram(buckets: buckets, peakStart: nil, inWindowShare: 0, secondaryStart: nil)
        }

        // Best 3-hour run, scanned circularly (the ±90-minute window the
        // suggestion engine uses, D10, is exactly three hourly buckets).
        // Ties break to the earliest start on the 5a axis.
        func windowSum(_ start: Int) -> Int {
            (0..<3).reduce(0) { $0 + buckets[(start + $1) % 24] }
        }
        let peakStart = (0..<24).max { a, b in
            (windowSum(a), b) < (windowSum(b), a)
        } ?? 0
        let peakSum = windowSum(peakStart)

        // Secondary window (C4): the best run that shares no bucket with
        // the peak, qualified on its own evidence floor so Mochi never
        // narrates noise.
        let secondaryStart = (0..<24)
            .filter { circularBucketDistance($0, peakStart) >= 3 }
            .max { a, b in (windowSum(a), b) < (windowSum(b), a) }
            .flatMap { start -> Int? in
                let sum = windowSum(start)
                let inWindow = entries.filter { bucketOffset(of: $0, from: start) < 3 }
                guard sum >= BestHoursConstants.secondWindMin,
                      Set(inWindow.map(\.day)).count >= BestHoursConstants.secondWindDates,
                      Double(sum) >= BestHoursConstants.secondWindShareRatio * Double(peakSum)
                else { return nil }
                return start
            }

        return Histogram(
            buckets: buckets,
            peakStart: peakStart,
            inWindowShare: Double(peakSum) / Double(total),
            secondaryStart: secondaryStart
        )
    }

    private static func circularBucketDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 24 - d)
    }

    private static func bucketOffset(of entry: Entry, from start: Int) -> Int {
        (axisMinute(entry.localMinute) / 60 - start + 24) % 24
    }

    // MARK: - Card 2 · per-weekday rows

    struct WeekdayRow: Equatable {
        /// Calendar numbering, 1 = Sunday ... 7 = Saturday.
        let weekday: Int
        /// Day-capped completions in the row.
        let count: Int
        let dateCount: Int
        /// D5: enough evidence for the middle-half capsule.
        let qualifies: Bool
        // Axis minutes (0..<1440 past 5a); nil when the row has no data.
        let first: Int?
        let last: Int?
        /// Middle half, only when the row qualifies.
        let q1: Int?
        let q3: Int?
        /// Circular center of the row's completions - the typical dot,
        /// shown for any row with data (D4).
        let typical: Int?
    }

    /// Seven rows ordered by the calendar's first weekday. Each entry lands
    /// in its AXIS day's row: a 2am completion belongs to the previous
    /// day's late night (the 5a boundary, D3), matching where the shared
    /// axis draws it. Per-day contributions are capped at
    /// `ObservationConstants.dayCap` so one heroic day can't reshape a row.
    static func weekdayRows(entries: [Entry], calendar: Calendar) -> [WeekdayRow] {
        var byWeekday: [Int: [CivilDay: [Entry]]] = [:]
        for entry in entries {
            let axisDay = entry.localMinute < axisOriginMinute ? entry.day.advanced(by: -1) : entry.day
            byWeekday[axisDay.weekday, default: [:]][axisDay, default: []].append(entry)
        }

        return (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            let byDay = byWeekday[weekday] ?? [:]
            // Day cap, stride-sampled over the minute-sorted entries (the
            // observation engine's rule) - limits weight without biasing
            // toward one end of the day.
            var capped: [Entry] = []
            for day in byDay.keys.sorted() {
                let sorted = byDay[day]!.sorted { axisMinute($0.localMinute) < axisMinute($1.localMinute) }
                let cap = ObservationConstants.dayCap
                if sorted.count <= cap {
                    capped.append(contentsOf: sorted)
                } else {
                    for pick in 0..<cap {
                        capped.append(sorted[pick * (sorted.count - 1) / Swift.max(cap - 1, 1)])
                    }
                }
            }
            let axisMinutes = capped.map { axisMinute($0.localMinute) }.sorted()
            let qualifies = capped.count >= BestHoursConstants.rowMin
                && byDay.keys.count >= BestHoursConstants.rowDates
            let typical = ObservationEngine.circularCenterMinute(of: capped.map(\.localMinute))
                .map(axisMinute)
            return WeekdayRow(
                weekday: weekday,
                count: capped.count,
                dateCount: byDay.keys.count,
                qualifies: qualifies,
                first: axisMinutes.first,
                last: axisMinutes.last,
                q1: qualifies ? quartile(axisMinutes, 0.25) : nil,
                q3: qualifies ? quartile(axisMinutes, 0.75) : nil,
                typical: typical
            )
        }
    }

    /// Linear-interpolated quartile over an already-sorted array.
    private static func quartile(_ sorted: [Int], _ p: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        let position = Double(sorted.count - 1) * p
        let low = Int(position)
        let high = Swift.min(low + 1, sorted.count - 1)
        let fraction = position - Double(low)
        return Int((Double(sorted[low]) * (1 - fraction) + Double(sorted[high]) * fraction).rounded())
    }

    // MARK: - Caption (C3/C4)

    /// The Mochi commentary line, generated from chart state - four states
    /// in priority order, qualitative, in the pet's voice. Generated lines
    /// rotate by state, so there is no FNV-1a pool here.
    static func caption(
        histogram: Histogram,
        rows: [WeekdayRow],
        petName: String,
        calendar: Calendar
    ) -> String {
        let anyQualified = rows.contains { $0.qualifies }
        let thin = rows.filter { !$0.qualifies }

        if let peakStart = histogram.peakStart, let secondaryStart = histogram.secondaryStart {
            let peak = bandPhrase(windowStart: peakStart)
            let secondary = bandPhrase(windowStart: secondaryStart)
            return "You get the most done in the \(peak), with a smaller second wind in the \(secondary). \(petName) sees it."
        }
        if anyQualified, !thin.isEmpty {
            return "\(petName) has a good read on your week. \(thinDaysPhrase(thin, calendar: calendar))"
        }
        if anyQualified, let peakStart = histogram.peakStart {
            return "You get the most done in the \(bandPhrase(windowStart: peakStart)). \(petName) sees the pattern."
        }
        return "Still learning your week. Here's your day so far."
    }

    /// The TimeOfDayBand of a 3-hour window's center, spoken lowercase -
    /// band names, never clock times, so the line stays warm and can't
    /// contradict the tiles.
    static func bandPhrase(windowStart start: Int) -> String {
        let centerLocalMinute = (start * 60 + 90 + axisOriginMinute) % 1440
        return TimeOfDayBand(minute: centerLocalMinute).rawValue
    }

    /// "Thursday and the weekend are still quiet." - a natural-language
    /// join of the sub-floor rows, with Sat+Sun folding into "the weekend".
    static func thinDaysPhrase(_ thin: [WeekdayRow], calendar: Calendar) -> String {
        var names: [String] = []
        let thinWeekdays = Set(thin.map(\.weekday))
        let foldsWeekend = thinWeekdays.contains(1) && thinWeekdays.contains(7)
        for row in thin {
            if row.weekday == 1 || row.weekday == 7 {
                guard foldsWeekend else {
                    names.append(calendar.standaloneWeekdaySymbols[row.weekday - 1])
                    continue
                }
                if !names.contains("the weekend") {
                    names.append("the weekend")
                }
            } else {
                names.append(calendar.standaloneWeekdaySymbols[row.weekday - 1])
            }
        }
        let joined: String
        switch names.count {
        case 1: joined = names[0]
        case 2: joined = "\(names[0]) and \(names[1])"
        default: joined = names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
        let verb = names.count == 1 ? "is" : "are"
        return "\(joined.prefix(1).uppercased() + joined.dropFirst()) \(verb) still quiet."
    }

    // MARK: - Labels

    /// "5a" / "12p" / "10p" for an axis bucket index.
    static func hourLabel(bucket: Int) -> String {
        let hour = (bucket + axisOriginMinute / 60) % 24
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case ..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }

    /// "10a to 1p" for the peak tile (C1) - a range, never a mean.
    static func peakRangeLabel(start: Int) -> String {
        "\(hourLabel(bucket: start)) to \(hourLabel(bucket: (start + 3) % 24))"
    }

    /// "10:50a" for a row's right-hand typical time, from an axis minute.
    static func timeLabel(axisMinute: Int) -> String {
        let localMinute = (axisMinute + axisOriginMinute) % 1440
        let hour24 = localMinute / 60
        let minute = localMinute % 60
        let suffix = hour24 < 12 ? "a" : "p"
        var hour = hour24 % 12
        if hour == 0 { hour = 12 }
        return String(format: "%d:%02d%@", hour, minute, suffix)
    }
}
