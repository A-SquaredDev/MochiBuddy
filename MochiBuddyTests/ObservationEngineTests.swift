//
//  ObservationEngineTests.swift
//  MochiBuddyTests
//
//  The observation engine's statistical integrity IS the product feature
//  (Personal Layer, Feature 4): every gate that looks like statistics is
//  brand protection. These tests pin the shipped-default thresholds -
//  they never mutate ObservationConstants (process-global, parallel suite).
//
//  Anchor: Dates.now = Wed 2026-07-08 10:00 local. Weekday numbering is
//  calendar-style: 1 = Sunday ... 7 = Saturday (Tuesday = 3, Thursday = 5).
//

import Foundation
import Testing
@testable import MochiBuddy

private let anchor = CivilDay("2026-07-08")!

/// Civil date string `offset` days from the anchor Wednesday.
private func day(_ offset: Int) -> String {
    anchor.advanced(by: offset).dateString
}

private func makeInputs(
    records: [CompletedTaskStat],
    intervals: [ObservationInterval] = [],
    logSince: Date? = Dates.days(-400),
    lists: Set<String> = [],
    now: Date = Dates.now,
    calendar: Calendar = .current
) -> ObservationEngine.Inputs {
    ObservationEngine.Inputs(
        records: records, intervals: intervals, logSince: logSince,
        knownListIds: lists, calendar: calendar, now: now
    )
}

private func candidate(
    _ kind: ObservationKind, in snapshot: ObservationEngine.Snapshot
) -> ObservationCandidate {
    snapshot.candidates.first { $0.kind == kind }!
}

private func gate(_ name: String, of candidate: ObservationCandidate) -> ObservationGateCheck {
    candidate.gates.first { $0.name == name }!
}

// MARK: - Civil days

@Suite("Observations · civil days")
struct CivilDayTests {

    @Test("parse, format, weekday, and arithmetic round-trip")
    func roundTrip() {
        let wednesday = CivilDay("2026-07-08")!
        #expect(wednesday.dateString == "2026-07-08")
        #expect(wednesday.weekday == 4, "Jul 8 2026 is a Wednesday")
        #expect(wednesday.advanced(by: 1).weekday == 5)
        #expect(wednesday.advanced(by: -7).dateString == "2026-07-01")
        #expect(CivilDay("2026-13-40") == nil)
        #expect(CivilDay("garbage") == nil)
    }

    @Test("the same instant lands on the civil day of the calendar's zone")
    func zoneDependence() {
        // 2026-07-08 03:00 UTC is still Jul 7 in Chicago, already Jul 8 in Tokyo.
        let instant = ISO8601DateFormatter().date(from: "2026-07-08T03:00:00Z")!
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        #expect(CivilDay(of: instant, in: chicago).dateString == "2026-07-07")
        #expect(CivilDay(of: instant, in: tokyo).dateString == "2026-07-08")
    }

    @Test("band boundaries: 05:00 / 12:00 / 17:00 / 21:00, night wraps")
    func bandBoundaries() {
        #expect(TimeOfDayBand(minute: 299) == .night)
        #expect(TimeOfDayBand(minute: 300) == .morning)
        #expect(TimeOfDayBand(minute: 719) == .morning)
        #expect(TimeOfDayBand(minute: 720) == .afternoon)
        #expect(TimeOfDayBand(minute: 1019) == .afternoon)
        #expect(TimeOfDayBand(minute: 1020) == .evening)
        #expect(TimeOfDayBand(minute: 1259) == .evening)
        #expect(TimeOfDayBand(minute: 1260) == .night)
        #expect(TimeOfDayBand(minute: 0) == .night)
    }
}

// MARK: - Local context capture

@Suite("Observations · completion-local context")
struct CompletionLocalContextTests {

    @Test("capture stamps the day and minute of the given zone, not the device's")
    func captureInZone() {
        let instant = ISO8601DateFormatter().date(from: "2026-07-08T03:30:00Z")!
        let tokyo = CompletionLocalContext.capture(
            at: instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )
        #expect(tokyo.localDate == "2026-07-08")
        #expect(tokyo.localMinute == 12 * 60 + 30)
        #expect(tokyo.timeZoneId == "Asia/Tokyo")

        let chicago = CompletionLocalContext.capture(
            at: instant, timeZone: TimeZone(identifier: "America/Chicago")!
        )
        #expect(chicago.localDate == "2026-07-07")
        #expect(chicago.localMinute == 22 * 60 + 30)
    }

    @Test("a record without stored context derives under the current zone, marked derived")
    func fallbackIsMarkedDerived() {
        let legacy = CompletedTaskStat(completedAt: Dates.now, dueAt: nil)
        #expect(legacy.localContextDerived, "the documented fallback must be honest")
        #expect(legacy.completedLocalDate == "2026-07-08")

        let stamped = makeStat(localDate: "2026-07-01", localMinute: 100)
        #expect(!stamped.localContextDerived)
    }

    @Test("completing a recurring task spawns the next occurrence with a stable series id")
    @MainActor
    func seriesIdInheritance() async {
        let repo = StubTaskRepository()
        let store = TaskCompletionStore(
            taskRepository: repo,
            rewardsStore: RewardsStore(profileRepository: StubProfileRepository()),
            membershipSession: MembershipSession()
        )
        let first = makeTask(id: "first", dueAt: Dates.hours(2), repeatRule: .daily)
        _ = await store.setCompleted(first, completed: true, currentCoins: 0, userId: "u")
        #expect(repo.addedDrafts.last?.seriesId == "first",
                "the first occurrence's id becomes the series identity")

        let spawned = makeTask(id: "second", dueAt: Dates.hours(26), repeatRule: .daily)
        var chained = spawned
        chained.seriesId = "first"
        _ = await store.setCompleted(chained, completed: true, currentCoins: 0, userId: "u")
        #expect(repo.addedDrafts.last?.seriesId == "first",
                "spawns inherit the original identity down the chain")
    }
}

// MARK: - Productive weekday

@Suite("Observations · productive weekday")
struct WeekdayObservationTests {

    /// 3 one-offs on each of 5 Tuesdays + 2+2 on two Mondays.
    private var tuesdayHeavy: [CompletedTaskStat] {
        var records: [CompletedTaskStat] = []
        for tuesday in [-1, -8, -15, -22, -29] {
            for slot in 0..<3 {
                records.append(makeStat(localDate: day(tuesday), localMinute: 540 + slot * 30))
            }
        }
        for monday in [-2, -9] {
            for slot in 0..<2 {
                records.append(makeStat(localDate: day(monday), localMinute: 540 + slot * 30))
            }
        }
        return records
    }

    @Test("enough spread one-off evidence qualifies the dominant weekday")
    func allGatesPass() {
        let snapshot = ObservationEngine.evaluate(makeInputs(records: tuesdayHeavy))
        let weekday = candidate(.weekday, in: snapshot)
        #expect(weekday.passesAllGates)
        #expect(weekday.conclusion == .weekday(3), "Tuesday")
    }

    @Test("below the evidence floor: silence, never a hedge")
    func belowFloor() {
        let few = Array(tuesdayHeavy.prefix(8))
        let snapshot = ObservationEngine.evaluate(makeInputs(records: few))
        let weekday = candidate(.weekday, in: snapshot)
        #expect(!weekday.passesAllGates)
        #expect(!gate("evidence floor", of: weekday).passed)
        #expect(!snapshot.qualified.contains { $0.kind == .weekday })
    }

    @Test("one heroic 20-completion day cannot mint the trait - the day cap")
    func burstResistance() {
        let burst = (0..<20).map { slot in
            makeStat(localDate: day(-1), localMinute: 480 + slot * 5)
        }
        let weekday = candidate(.weekday, in: ObservationEngine.evaluate(makeInputs(records: burst)))
        #expect(!weekday.passesAllGates)
        #expect(!gate("evidence floor", of: weekday).passed,
                "a single day contributes at most dayCap completions")
        #expect(!gate("distinct weeks", of: weekday).passed)
    }

    @Test("a near-tie fails the margin gate - ties are the 'when unsure' case")
    func tieIsSilence() {
        var records: [CompletedTaskStat] = []
        for tuesday in [-1, -8, -15, -22] {
            for slot in 0..<3 { records.append(makeStat(localDate: day(tuesday), localMinute: 500 + slot)) }
        }
        for thursday in [-6, -13, -20, -27] {
            for slot in 0..<3 { records.append(makeStat(localDate: day(thursday), localMinute: 500 + slot)) }
        }
        let weekday = candidate(.weekday, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(!weekday.passesAllGates)
        #expect(!gate("runner-up margin", of: weekday).passed)
    }

    @Test("recurring completions are excluded - the circularity trap")
    func recurringExcluded() {
        let recurring = (0..<6).flatMap { week in
            (0..<3).map { slot in
                makeStat(
                    seriesId: "habit", localDate: day(-1 - week * 7),
                    localMinute: 540 + slot * 10, isRecurring: true
                )
            }
        }
        let weekday = candidate(.weekday, in: ObservationEngine.evaluate(makeInputs(records: recurring)))
        #expect(!weekday.passesAllGates,
                "a weekly-Tuesday task must not produce 'productive on Tuesdays'")
        #expect(weekday.evidenceCount == 0)
    }
}

// MARK: - Productive time of day

@Suite("Observations · time of day")
struct TimeOfDayObservationTests {

    /// 3 morning completions on each of 7 spread dates + a few evenings.
    private var morningHeavy: [CompletedTaskStat] {
        var records: [CompletedTaskStat] = []
        for offset in [-1, -4, -8, -12, -16, -20, -24] {
            for slot in 0..<3 {
                records.append(makeStat(localDate: day(offset), localMinute: 420 + slot * 40))
            }
        }
        for offset in [-2, -10, -18] {
            records.append(makeStat(localDate: day(offset), localMinute: 19 * 60))
        }
        return records
    }

    @Test("a dominant band with spread evidence qualifies")
    func allGatesPass() {
        let timeOfDay = candidate(.timeOfDay, in: ObservationEngine.evaluate(makeInputs(records: morningHeavy)))
        #expect(timeOfDay.passesAllGates)
        #expect(timeOfDay.conclusion == .band(.morning))
    }

    @Test("recurring completions COUNT here - when in the day is real behavior")
    func recurringIncluded() {
        let recurringMornings = (0..<21).map { offset in
            makeStat(
                seriesId: "vitamins", localDate: day(-offset),
                localMinute: 7 * 60, isRecurring: true
            )
        }
        let timeOfDay = candidate(.timeOfDay, in: ObservationEngine.evaluate(makeInputs(records: recurringMornings)))
        #expect(timeOfDay.passesAllGates)
        #expect(timeOfDay.conclusion == .band(.morning))
    }

    @Test("a night-shift rhythm qualifies like any other band")
    func nightBandQualifies() {
        var records: [CompletedTaskStat] = []
        for offset in [-1, -4, -8, -12, -16, -20, -24] {
            records.append(makeStat(localDate: day(offset), localMinute: 23 * 60 + 30))
            records.append(makeStat(localDate: day(offset), localMinute: 30))
            records.append(makeStat(localDate: day(offset), localMinute: 22 * 60))
        }
        let timeOfDay = candidate(.timeOfDay, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(timeOfDay.passesAllGates)
        #expect(timeOfDay.conclusion == .band(.night))
    }

    @Test("one 20-completion morning fails floor and spread together")
    func burstResistance() {
        let burst = (0..<20).map { slot in
            makeStat(localDate: day(-1), localMinute: 400 + slot * 10)
        }
        let timeOfDay = candidate(.timeOfDay, in: ObservationEngine.evaluate(makeInputs(records: burst)))
        #expect(!timeOfDay.passesAllGates)
        #expect(!gate("evidence floor", of: timeOfDay).passed)
        #expect(!gate("distinct dates", of: timeOfDay).passed)
    }
}

// MARK: - Momentum

@Suite("Observations · momentum")
struct MomentumObservationTests {

    private func spread(_ count: Int, over dayOffsets: ClosedRange<Int>) -> [CompletedTaskStat] {
        (0..<count).map { index in
            let span = dayOffsets.count
            let offset = dayOffsets.lowerBound + (index * span) / count
            return makeStat(localDate: day(offset), localMinute: 600 + index % 60)
        }
    }

    @Test("a genuine rise qualifies at compose time")
    func risingQualifies() {
        let records = spread(10, over: -41...(-21)) + spread(21, over: -20...0)
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records))
        #expect(candidate(.momentum, in: snapshot).passesAllGates)
        #expect(snapshot.qualified.contains { $0.conclusion == .momentumRising })
    }

    @Test("a falling trend is silence, never a concerned observation")
    func fallingIsSilence() {
        let records = spread(21, over: -41...(-21)) + spread(10, over: -20...0)
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records))
        #expect(!candidate(.momentum, in: snapshot).passesAllGates)
    }

    @Test("vacation days leave momentum entirely - the day AND its completions")
    func vacationNormalization() {
        // Older half: steady 10. Recent half: a 15-completion vacation
        // burst plus 5 ordinary - without exclusion this reads as a surge.
        let vacationStart = Dates.days(-14)
        let vacationEnd = Dates.days(-8)
        var records = spread(10, over: -41...(-21)) + spread(5, over: -6...0)
        for index in 0..<15 {
            records.append(makeStat(localDate: day(-13 + index % 6), localMinute: 700 + index))
        }
        let withExclusion = ObservationEngine.evaluate(makeInputs(
            records: records,
            intervals: [ObservationInterval(kind: .vacation, start: vacationStart, end: vacationEnd)]
        ))
        #expect(!candidate(.momentum, in: withExclusion).passesAllGates,
                "a vacation burst must not manufacture a rising trend")

        let withoutExclusion = ObservationEngine.evaluate(makeInputs(records: records))
        #expect(candidate(.momentum, in: withoutExclusion).passesAllGates,
                "sanity: the same data WOULD qualify if the interval were unknown to the log")
    }

    @Test("halves touching pre-log days force silence - the honest-fallback rule")
    func preLogSilence() {
        let records = spread(10, over: -41...(-21)) + spread(21, over: -20...0)
        let snapshot = ObservationEngine.evaluate(makeInputs(
            records: records, logSince: Dates.days(-30)
        ))
        let momentum = candidate(.momentum, in: snapshot)
        #expect(!momentum.passesAllGates)
        #expect(!gate("eligibility known", of: momentum).passed,
                "no claimed normalization without a data source")
    }

    @Test("a relative jump below the absolute delta is not a trend")
    func relativeOnlyJumpFails() {
        // 10 vs 13 on 21-day halves: ratio 1.3 exactly, delta 0.14/day.
        let records = spread(10, over: -41...(-21)) + spread(13, over: -20...0)
        let momentum = candidate(.momentum, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(!momentum.passesAllGates)
        #expect(!gate("absolute delta", of: momentum).passed)
    }

    @Test("a recent resubscription cannot manufacture a rising trend")
    func lapseExcluded() {
        // Heavy activity after reactivating 12 days ago; lapse before that.
        let records = spread(10, over: -41...(-21)) + spread(21, over: -11...0)
        let snapshot = ObservationEngine.evaluate(makeInputs(
            records: records,
            intervals: [ObservationInterval(kind: .lapse, start: Dates.days(-100), end: Dates.days(-12))]
        ))
        let momentum = candidate(.momentum, in: snapshot)
        #expect(!momentum.passesAllGates,
                "lapse days are ineligible the same way vacation days are")
    }
}

// MARK: - List return

@Suite("Observations · list return")
struct ListReturnObservationTests {

    private func history(list: String, endingAt offset: Int, count: Int) -> [CompletedTaskStat] {
        (0..<count).map { index in
            makeStat(localDate: day(offset - index * 2), localMinute: 610, listId: list)
        }
    }

    @Test("a completion after a real quiet spell fires the event")
    func fires() {
        let records = history(list: "personal", endingAt: -20, count: 5)
            + [makeStat(localDate: day(-2), localMinute: 615, listId: "personal")]
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records, lists: ["personal"]))
        let listReturn = candidate(.listReturn, in: snapshot)
        #expect(listReturn.passesAllGates)
        #expect(listReturn.conclusion == .listReturn(listId: "personal"))
        #expect(snapshot.qualified.contains {
            $0.kind == .listReturn && $0.stableSince == day(-2)
        })
    }

    @Test("thin prior history keeps it silent - the list never really mattered")
    func historyFloor() {
        let records = history(list: "personal", endingAt: -20, count: 4)
            + [makeStat(localDate: day(-2), localMinute: 615, listId: "personal")]
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records, lists: ["personal"]))
        #expect(!candidate(.listReturn, in: snapshot).passesAllGates)
    }

    @Test("a quiet spell that was actually a vacation is not absence")
    func vacationQuietSpellSuppressed() {
        let records = history(list: "personal", endingAt: -20, count: 5)
            + [makeStat(localDate: day(-2), localMinute: 615, listId: "personal")]
        let snapshot = ObservationEngine.evaluate(makeInputs(
            records: records,
            intervals: [ObservationInterval(kind: .vacation, start: Dates.days(-15), end: Dates.days(-10))],
            lists: ["personal"]
        ))
        #expect(!candidate(.listReturn, in: snapshot).passesAllGates,
                "absence wasn't behavior")
    }

    @Test("the event expires after a week")
    func expires() {
        let records = history(list: "personal", endingAt: -30, count: 5)
            + [makeStat(localDate: day(-10), localMinute: 615, listId: "personal")]
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records, lists: ["personal"]))
        #expect(!candidate(.listReturn, in: snapshot).passesAllGates)
    }

    @Test("only surviving lists are ever referenced")
    func deletedListIgnored() {
        let records = history(list: "deleted", endingAt: -20, count: 5)
            + [makeStat(localDate: day(-2), localMinute: 615, listId: "deleted")]
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records, lists: []))
        #expect(candidate(.listReturn, in: snapshot).conclusion == nil)
    }
}

// MARK: - Comeback

@Suite("Observations · comeback")
struct ComebackObservationTests {

    /// An overdue-then-completed event `late` seconds past a timed due.
    private func comebackEvent(
        offset: Int, late: TimeInterval, taskId: String = UUID().uuidString, seriesId: String? = nil
    ) -> CompletedTaskStat {
        let due = Dates.days(offset)
        return makeStat(
            taskId: taskId, seriesId: seriesId, localDate: day(offset),
            localMinute: 700, completedAt: due.addingTimeInterval(late),
            dueAt: due, hasTime: true
        )
    }

    @Test("diverse fast catches qualify the trait")
    func qualifies() {
        let records = (0..<8).map { index in
            comebackEvent(offset: -2 - index * 4, late: 2 * 3600)
        }
        let comeback = candidate(.comeback, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(comeback.passesAllGates)
    }

    @Test("the p75 gate stops fast saves from hiding week-long stalls")
    func p75CatchesStalls() {
        let records = (0..<5).map { comebackEvent(offset: -2 - $0 * 4, late: 2 * 3600) }
            + (0..<3).map { comebackEvent(offset: -25 - $0 * 4, late: 100 * 3600) }
        let comeback = candidate(.comeback, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(!comeback.passesAllGates)
        #expect(gate("median catch-up", of: comeback).passed, "the median alone would lie")
        #expect(!gate("p75 catch-up", of: comeback).passed)
    }

    @Test("one habitually-late habit cannot mint the trait - series diversity")
    func seriesDiversity() {
        let records = (0..<8).map { index in
            comebackEvent(offset: -2 - index * 4, late: 2 * 3600, seriesId: "same-habit")
        }
        let comeback = candidate(.comeback, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(!comeback.passesAllGates)
        #expect(!gate("distinct tasks", of: comeback).passed)
    }

    @Test("date-only lateness measures from the end of the due day, in the completion's zone")
    func dateOnlyLateness() {
        // Due Jul 1 (date-only, Chicago). Completed Jul 2 09:00 Chicago:
        // 9h past the boundary - a fast catch, deliberately.
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        let dueInstant = chicago.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 9))!
        let boundary = chicago.startOfDay(for: dueInstant).addingTimeInterval(86_400)
        let records = (0..<8).map { index -> CompletedTaskStat in
            makeStat(
                localDate: "2026-07-0\(2 + index % 3)", localMinute: 540,
                completedAt: boundary.addingTimeInterval(9 * 3600),
                dueAt: dueInstant, hasTime: false
            )
        }
        let comeback = candidate(.comeback, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(gate("median catch-up", of: comeback).passed,
                "next-morning completion reads as a fast catch")
    }

    @Test("undated completions produce no comeback signal")
    func undatedSilent() {
        let records = (0..<10).map { makeStat(localDate: day(-$0 * 3), localMinute: 400) }
        let comeback = candidate(.comeback, in: ObservationEngine.evaluate(makeInputs(records: records)))
        #expect(comeback.conclusion == nil)
        #expect(!comeback.passesAllGates)
    }
}

// MARK: - Deterministic hysteresis

@Suite("Observations · deterministic replay")
struct ObservationReplayTests {

    private func tuesdays(from: Int, to: Int) -> [CompletedTaskStat] {
        stride(from: from, through: to, by: 7).flatMap { offset in
            (0..<3).map { slot in
                makeStat(localDate: day(offset), localMinute: 540 + slot * 20)
            }
        }
    }

    private func thursdays(from: Int, to: Int) -> [CompletedTaskStat] {
        stride(from: from, through: to, by: 7).flatMap { offset in
            (0..<3).map { slot in
                makeStat(localDate: day(offset), localMinute: 540 + slot * 20)
            }
        }
    }

    @Test("an incumbent forms, then hands over when the behavior truly changes")
    func switchTransition() {
        // Tuesdays dominate the old regime, Thursdays the new one.
        let records = tuesdays(from: -120, to: -50) + thursdays(from: -48, to: -1)
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records))
        let timeline = snapshot.timelines.first { $0.kind == .weekday }!

        #expect(timeline.days.contains { $0.incumbent == .weekday(3) },
                "Tuesday held the seat in the old regime")
        #expect(timeline.incumbent == .weekday(5), "Thursday holds it now")
        #expect(snapshot.qualified.contains { $0.kind == .weekday && $0.conclusion == .weekday(5) })
    }

    @Test("an incumbent nothing replaces retires to silence, never lingers")
    func retireTransition() {
        let records = tuesdays(from: -120, to: -55)
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records))
        let timeline = snapshot.timelines.first { $0.kind == .weekday }!

        #expect(timeline.days.contains { $0.incumbent == .weekday(3) })
        #expect(timeline.incumbent == nil, "a stale conclusion never lingers for months")
        #expect(!snapshot.qualified.contains { $0.kind == .weekday })
    }

    @Test("a candidate must pass 14 consecutive snapshots before it speaks")
    func stickinessBeforeFirstQualification() {
        // Exactly 5 Tuesdays x 3 one-offs: today's snapshot clears every
        // gate, but only the last couple of snapshots did - no 14-day
        // streak, so production hears NOTHING yet.
        let records = tuesdays(from: -29, to: -1)
        let snapshot = ObservationEngine.evaluate(makeInputs(records: records))
        let today = candidate(.weekday, in: snapshot)

        #expect(today.passesAllGates, "sanity: the single-snapshot gates do pass today")
        #expect(!snapshot.qualified.contains { $0.kind == .weekday },
                "an incumbent exists only after a full sticky streak")
        #expect(snapshot.timelines.first { $0.kind == .weekday }!.incumbent == nil)
    }

    @Test("same inputs, same output - twice, bit-identical")
    func determinism() {
        let records = tuesdays(from: -120, to: -50) + thursdays(from: -41, to: -1)
            + (0..<8).map { comebackIndex in
                makeStat(
                    localDate: day(-2 - comebackIndex * 4), localMinute: 700,
                    completedAt: Dates.days(-2 - comebackIndex * 4).addingTimeInterval(3600),
                    dueAt: Dates.days(-2 - comebackIndex * 4), hasTime: true
                )
            }
        let inputs = makeInputs(records: records, lists: ["a", "b"])
        #expect(ObservationEngine.evaluate(inputs) == ObservationEngine.evaluate(inputs))
    }

    @Test("the device's current zone never re-buckets stored history")
    func currentZoneIndependence() {
        // The same instant is the same civil day in UTC and Tokyo; records
        // carry Chicago context. Conclusions must be bit-identical.
        let instant = ISO8601DateFormatter().date(from: "2026-07-08T00:00:00Z")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let records = tuesdays(from: -120, to: -50) + thursdays(from: -41, to: -1)
        let inUTC = ObservationEngine.evaluate(makeInputs(records: records, now: instant, calendar: utc))
        let inTokyo = ObservationEngine.evaluate(makeInputs(records: records, now: instant, calendar: tokyo))
        #expect(inUTC == inTokyo, "relocation must never rewrite apparent behavior")
    }
}

// MARK: - Distribution (Feature 5's contract)

@Suite("Observations · distribution")
struct DistributionTests {

    @Test("list scope holds when the list alone clears the floor")
    func listScope() {
        let records = (0..<24).map { index in
            makeStat(localDate: day(-index), localMinute: 500 + index, listId: "work")
        }
        let result = ObservationEngine.timeOfDayDistribution(
            listId: "work", inputs: makeInputs(records: records, lists: ["work"])
        )
        #expect(result.scopeUsed == .list("work"))
        #expect(result.evidenceCount >= 20)
    }

    @Test("a thin list falls back globally - and SAYS so")
    func globalFallbackIsExplicit() {
        let thin = (0..<5).map { makeStat(localDate: day(-$0), localMinute: 400, listId: "hobby") }
        let global = (0..<25).map { makeStat(localDate: day(-$0), localMinute: 900) }
        let result = ObservationEngine.timeOfDayDistribution(
            listId: "hobby", inputs: makeInputs(records: thin + global, lists: ["hobby"])
        )
        #expect(result.scopeUsed == .globalFallback,
                "a caller can never mistake a fallback for list evidence")
    }

    @Test("circular math clusters 23:30 and 00:30 at midnight, never noon")
    func circularClustering() {
        #expect(ObservationEngine.circularCenterMinute(of: [1410, 30]) == 0)
        let nearMidnight = ObservationEngine.circularCenterMinute(of: [1400, 1420, 20, 40])!
        #expect(nearMidnight >= 1380 || nearMidnight <= 60)
        #expect(ObservationEngine.circularCenterMinute(of: [720]) == 720)
        #expect(ObservationEngine.circularCenterMinute(of: []) == nil)
    }

    @Test("series scope keeps timed completions only, and names itself")
    func seriesScopeTimedOnly() {
        let timed = (0..<10).map { index in
            makeStat(seriesId: "s1", localDate: day(-1 - index), localMinute: 1200, hasTime: true,
                     isRecurring: true)
        }
        let dateOnly = (0..<3).map { index in
            makeStat(seriesId: "s1", localDate: day(-20 - index), localMinute: 900, hasTime: false,
                     isRecurring: true)
        }
        let other = (0..<5).map { index in
            makeStat(taskId: "other", localDate: day(-1 - index), localMinute: 600, hasTime: true)
        }
        let result = ObservationEngine.suggestionDistribution(
            scope: .series("s1"),
            inputs: makeInputs(records: timed + dateOnly + other)
        )
        #expect(result.scopeUsed == .series("s1"))
        #expect(result.evidenceCount == 10, "date-only rows are not evidence about a due TIME")
        #expect(result.entries.allSatisfy { $0.minute == 1200 })
    }

    @Test("suggestion entries carry provenance: identity, civil day, rescheduleCount")
    func entryProvenance() {
        let records = [
            makeStat(taskId: "t1", seriesId: "s1", localDate: day(-1), localMinute: 600,
                     rescheduleCount: 2),
            makeStat(taskId: "t2", localDate: day(-2), localMinute: 700, rescheduleCount: nil),
        ]
        let result = ObservationEngine.suggestionDistribution(
            scope: .global, inputs: makeInputs(records: records)
        )
        func byMinute(_ minute: Int) -> DistributionResult.Entry {
            result.entries.first { $0.minute == minute }!
        }
        #expect(byMinute(600).identity == "s1", "seriesId over taskId - one habit, one identity")
        #expect(byMinute(600).rescheduleCount == 2)
        #expect(byMinute(600).day == day(-1))
        #expect(byMinute(700).identity == "t2")
        #expect(byMinute(700).rescheduleCount == nil, "unknown stays unknown, never 0")
    }

    @Test("the day cap applies AFTER scope filtering - a scope's cap is its own")
    func dayCapAfterFilter() {
        // Five same-day series completions + five same-day others: the
        // series scope caps to 3 of ITS OWN, not 3 of the mixed day.
        let series = (0..<5).map { index in
            makeStat(seriesId: "s1", localDate: day(-1), localMinute: 1000 + index, hasTime: true,
                     isRecurring: true)
        }
        let other = (0..<5).map { index in
            makeStat(taskId: "o\(index)", localDate: day(-1), localMinute: 500 + index)
        }
        let result = ObservationEngine.suggestionDistribution(
            scope: .series("s1"), inputs: makeInputs(records: series + other)
        )
        #expect(result.evidenceCount == 3)
        #expect(result.entries.allSatisfy { $0.minute >= 1000 })
    }
}
