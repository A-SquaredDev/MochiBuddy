//
//  SuggestionEngineTests.swift
//  MochiBuddyTests
//
//  The suggestion pipeline's statistical honesty IS the feature (Personal
//  Layer, Feature 5): qualification on raw day-capped counts, silence on
//  every doubt, provenance that can't overreach. Constants are pinned by
//  fixture construction against the shipped defaults - never by mutating
//  SuggestionConstants (process-global, parallel suite).
//
//  Anchor: Dates.now = Wed 2026-07-08 10:00 local.
//

import Foundation
import Testing
@testable import MochiBuddy

private let anchor = CivilDay("2026-07-08")!

private func day(_ offset: Int) -> String {
    anchor.advanced(by: offset).dateString
}

private func entry(
    minute: Int, day dayString: String, identity: String = "t1", reschedules: Int? = 0
) -> DistributionResult.Entry {
    DistributionResult.Entry(
        minute: minute, day: dayString, identity: identity, rescheduleCount: reschedules
    )
}

/// A qualified-by-construction cluster: `count` completions at `minute`,
/// one per day walking backward from the anchor, distinct identities.
private func cluster(
    _ count: Int, minute: Int, identityPrefix: String = "t", reschedules: Int? = 0,
    startingDayOffset: Int = -1
) -> [DistributionResult.Entry] {
    (0..<count).map { index in
        entry(
            minute: minute,
            day: day(startingDayOffset - index),
            identity: "\(identityPrefix)\(index)",
            reschedules: reschedules
        )
    }
}

private func dist(
    _ entries: [DistributionResult.Entry],
    scope: DistributionResult.Scope = .globalFallback
) -> DistributionResult {
    DistributionResult(entries: entries, scopeUsed: scope)
}

/// An open, un-lapsed context due tomorrow with an empty bedtime window
/// (never trips the guardrail unless a test wants it to).
private func makeContext(
    series: DistributionResult? = nil,
    list: DistributionResult? = nil,
    global: DistributionResult = dist([]),
    bedtime: BedtimeWindow = BedtimeWindow(startMinutes: 0, endMinutes: 0),
    isLapsed: Bool = false,
    today: String = day(0),
    nowMinute: Int = 600
) -> SuggestionEngine.Context {
    SuggestionEngine.Context(
        series: series, list: list, global: global,
        bedtime: bedtime, isLapsed: isLapsed, today: today, nowMinute: nowMinute
    )
}

private func makeSnapshot(
    listId: String? = nil,
    isRecurring: Bool = false,
    hasTime: Bool = false,
    scheduledMinute: Int? = nil,
    dueDay: String? = day(1),
    isAppleSource: Bool = false
) -> SuggestionEngine.TaskSnapshot {
    SuggestionEngine.TaskSnapshot(
        listId: listId, isRecurring: isRecurring, hasTime: hasTime,
        scheduledMinute: scheduledMinute, dueDay: dueDay, isAppleSource: isAppleSource
    )
}

// MARK: - Qualification gates (raw day-capped counts)

@Suite("Suggestions · gates")
struct SuggestionGateTests {

    @Test("a real cluster qualifies and proposes its friendly time")
    func happyPath() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(cluster(15, minute: 600))),
            dismissedAt: nil
        )
        let proposal = try! #require(result.proposal)
        #expect(proposal.tier == .global)
        #expect(proposal.displayedMinute == 600)
        #expect(result.blocked == nil)
    }

    @Test("evidence floor: 14 day-capped completions is silence")
    func evidenceFloor() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(cluster(14, minute: 600))),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .evidence)
    }

    @Test("distinct-date floor: 15 completions on 4 dates is silence")
    func dateFloor() {
        let entries = (0..<15).map { index in
            entry(minute: 600, day: day(-1 - index % 4), identity: "t\(index)")
        }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(entries)),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .evidence)
    }

    @Test("peak share: an even spread across the day is silence")
    func peakShare() {
        // 16 completions, one per 90 minutes - no window reaches 35%.
        let entries = (0..<16).map { index in
            entry(minute: index * 90, day: day(-1 - index % 6), identity: "t\(index)")
        }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(entries)),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .peakShare)
    }

    @Test("peak-date spread: a two-day cluster fails even when the global date floor passes")
    func peakDateSpread() {
        // 6 at 10:00 from only 2 distinct days; 9 diffuse singletons far
        // away across 9 other days keep total evidence + date floors
        // green without minting a rival window.
        let peak = (0..<6).map { index in
            entry(minute: 600, day: day(-1 - index % 2), identity: "p\(index)")
        }
        let diffuse = [780, 930, 1080, 1230, 1380, 90, 240, 330, 390]
        let elsewhere = diffuse.enumerated().map { index, minute in
            entry(minute: minute, day: day(-3 - index), identity: "e\(index)")
        }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(peak + elsewhere)),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .peakDates)
    }

    @Test("bimodal means silence, by construction: 6 at 9am, 6 at 6pm, 3 scattered")
    func bimodal() {
        let nine = (0..<6).map { entry(minute: 540, day: day(-1 - $0), identity: "a\($0)") }
        let six = (0..<6).map { entry(minute: 1080, day: day(-1 - $0), identity: "b\($0)") }
        let scattered = [
            entry(minute: 0, day: day(-7), identity: "c0"),
            entry(minute: 240, day: day(-8), identity: "c1"),
            entry(minute: 780, day: day(-9), identity: "c2"),
        ]
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(nine + six + scattered)),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .runnerUp, "two real patterns get no tiebreak")
    }

    @Test("boundary-exact: 15 completions, 5 dates, share exactly 0.35+ qualifies")
    func boundaryExact() {
        // 6 clustered of 15 = 0.40 share; runner-up window holds 3 of the
        // far spread = 0.20; margin 0.20 >= 0.10.
        let peak = (0..<6).map { entry(minute: 600, day: day(-1 - $0 % 5), identity: "p\($0)") }
        let rest = (0..<9).map { index in
            entry(minute: (900 + index * 55) % 1440, day: day(-1 - index % 5), identity: "r\(index)")
        }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(peak + rest)),
            dismissedAt: nil
        )
        // The exact runner-up depends on the spread; what is pinned here
        // is that a decisive 0.40 cluster with a diffuse remainder shows.
        #expect(result.proposal != nil)
        #expect(result.proposal?.displayedMinute == 600)
    }

    @Test("determinism: same inputs, same evaluation, every time")
    func determinism() {
        let context = makeContext(global: dist(cluster(15, minute: 611)))
        let task = makeSnapshot()
        let first = SuggestionEngine.evaluateNewTime(task: task, context: context, dismissedAt: nil)
        let second = SuggestionEngine.evaluateNewTime(task: task, context: context, dismissedAt: nil)
        #expect(first == second)
        #expect(first.proposal != nil)
    }
}

// MARK: - Circular math + rounding

@Suite("Suggestions · circular math")
struct SuggestionCircularTests {

    @Test("friendly rounding: nearest half hour, quarter ties earlier")
    func rounding() {
        #expect(SuggestionEngine.friendlyRounded(600) == 600)
        #expect(SuggestionEngine.friendlyRounded(614) == 600)
        #expect(SuggestionEngine.friendlyRounded(615) == 600, "exact quarter tie rounds EARLIER")
        #expect(SuggestionEngine.friendlyRounded(616) == 630)
        #expect(SuggestionEngine.friendlyRounded(644) == 630)
        #expect(SuggestionEngine.friendlyRounded(645) == 630, "tie rounds earlier")
        #expect(SuggestionEngine.friendlyRounded(646) == 660)
    }

    @Test("rounding never crosses the date boundary: 23:45 and 23:50 both fall to 23:30")
    func dateBoundary() {
        #expect(SuggestionEngine.friendlyRounded(1425) == 1410)
        #expect(SuggestionEngine.friendlyRounded(1430) == 1410, "next-day 00:00 is never proposed")
        #expect(SuggestionEngine.friendlyRounded(1439) == 1410)
        #expect(SuggestionEngine.friendlyRounded(10) == 0, "same-day midnight is fine")
    }

    @Test("circular distance wraps: 21:00 vs 09:00 is 12h, 23:00 vs 01:00 is 2h")
    func distance() {
        #expect(SuggestionEngine.circularDistance(1260, 540) == 720)
        #expect(SuggestionEngine.circularDistance(1380, 60) == 120)
        #expect(SuggestionEngine.circularDistance(0, 1439) == 1)
        #expect(SuggestionEngine.circularDistance(600, 600) == 0)
    }

    @Test("a cross-midnight cluster peaks at midnight, never at noon")
    func crossMidnightPeak() {
        let entries = [
            entry(minute: 1400, day: day(-1), identity: "a"),
            entry(minute: 1420, day: day(-2), identity: "b"),
            entry(minute: 20, day: day(-3), identity: "c"),
            entry(minute: 40, day: day(-4), identity: "d"),
        ] + (0..<11).map { index in
            entry(minute: (1410 + index * 5) % 1440, day: day(-1 - index % 5), identity: "e\(index)")
        }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(entries)),
            dismissedAt: nil
        )
        let proposal = try! #require(result.proposal)
        #expect(proposal.displayedMinute >= 1380 || proposal.displayedMinute <= 60)
    }

    @Test("weighted circular center honors weights")
    func weightedCenter() {
        let center = SuggestionEngine.weightedCircularCenter([
            (minute: 600, weight: 1), (minute: 660, weight: 3),
        ])!
        #expect(center == 645)
        #expect(SuggestionEngine.weightedCircularCenter([]) == nil)
    }
}

// MARK: - Reschedule weighting (shapes peaks, never qualifies)

@Suite("Suggestions · reschedule weighting")
struct SuggestionWeightTests {

    private func twoClusterEntries(reschedules: Int?) -> [DistributionResult.Entry] {
        cluster(8, minute: 600, identityPrefix: "a")
            + cluster(8, minute: 690, identityPrefix: "b", reschedules: reschedules)
    }

    @Test("rescheduled completions pull the peak of a qualified distribution")
    func weightsShapePeak() {
        let unweighted = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(twoClusterEntries(reschedules: 0))),
            dismissedAt: nil
        )
        // Both clusters weigh 1: the mean is a quarter tie, rounded earlier.
        #expect(unweighted.proposal?.displayedMinute == 630)

        let weighted = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(twoClusterEntries(reschedules: 3))),
            dismissedAt: nil
        )
        // The kept-moved cluster (weight 1.75x, capped) drags the peak
        // toward itself.
        #expect(weighted.proposal?.displayedMinute == 660)
    }

    @Test("nil rescheduleCount means weight 1 - unknown, never 'known unmoved'")
    func nilIsWeightOne() {
        let withNil = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(twoClusterEntries(reschedules: nil))),
            dismissedAt: nil
        )
        #expect(withNil.proposal?.displayedMinute == 630)
    }

    @Test("weights never help qualification: 14 heavily-rescheduled completions stay silent")
    func weightsNeverQualify() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(cluster(14, minute: 600, reschedules: 3))),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .evidence)
    }
}

// MARK: - Scope precedence (highest QUALIFYING scope)

@Suite("Suggestions · scope")
struct SuggestionScopeTests {

    @Test("a qualified series outranks a qualified list and global")
    func seriesWins() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(listId: "personal", isRecurring: true),
            context: makeContext(
                series: dist(cluster(8, minute: 1200, identityPrefix: "s"), scope: .series("s1")),
                list: dist(cluster(20, minute: 600), scope: .list("personal")),
                global: dist(cluster(25, minute: 600))
            ),
            dismissedAt: nil
        )
        let proposal = try! #require(result.proposal)
        #expect(proposal.tier == .series)
        #expect(proposal.displayedMinute == 1200)
    }

    @Test("a rich-but-unqualified series loses to a qualified list")
    func unqualifiedSeriesFallsThrough() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(listId: "personal", isRecurring: true),
            context: makeContext(
                // Six completions: below the series floor of 8.
                series: dist(cluster(6, minute: 1200, identityPrefix: "s"), scope: .series("s1")),
                list: dist(cluster(20, minute: 600), scope: .list("personal")),
                global: dist(cluster(25, minute: 900))
            ),
            dismissedAt: nil
        )
        let proposal = try! #require(result.proposal)
        #expect(proposal.tier == .list)
        #expect(proposal.displayedMinute == 600)
        #expect(proposal.listId == "personal")
    }

    @Test("list concentration guard: one habit over 40% falls through to global")
    func listConcentration() {
        // 20 list completions, 9 from one identity (45% > 40%).
        let dominant = (0..<9).map { entry(minute: 600, day: day(-1 - $0), identity: "habit") }
        let others = (0..<11).map { entry(minute: 600, day: day(-1 - $0), identity: "o\($0)") }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(listId: "personal"),
            context: makeContext(
                list: dist(dominant + others, scope: .list("personal")),
                global: dist(cluster(25, minute: 900))
            ),
            dismissedAt: nil
        )
        let proposal = try! #require(result.proposal)
        #expect(proposal.tier == .global, "one series can't speak for a list")
        #expect(proposal.displayedMinute == 900)
    }

    @Test("list identity floor: two identities can't wear a list costume")
    func listIdentityFloor() {
        let entries = (0..<20).map {
            entry(minute: 600, day: day(-1 - $0 % 10), identity: $0 % 2 == 0 ? "a" : "b")
        }
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(listId: "personal"),
            context: makeContext(
                list: dist(entries, scope: .list("personal")),
                global: dist(cluster(25, minute: 900))
            ),
            dismissedAt: nil
        )
        #expect(result.proposal?.tier == .global)
    }

    @Test("nothing qualifies anywhere: silence with the widest scope's reason")
    func totalSilence() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(listId: "personal"),
            context: makeContext(
                list: dist(cluster(3, minute: 600), scope: .list("personal")),
                global: dist(cluster(5, minute: 600))
            ),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .evidence)
    }
}

// MARK: - Guardrails (silence, never a shifted time)

@Suite("Suggestions · guardrails")
struct SuggestionGuardrailTests {

    @Test("a rounded time inside the bedtime window is silenced, never clamped")
    func bedtime() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(
                global: dist(cluster(15, minute: 1380)),
                bedtime: .standard
            ),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .bedtime)
    }

    @Test("lead-time guard: a 10:00 chip at 9:45 today is silence, not 10:30")
    func leadTime() {
        let context = makeContext(global: dist(cluster(15, minute: 600)), nowMinute: 585)
        let today = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(dueDay: day(0)), context: context, dismissedAt: nil
        )
        #expect(today.proposal == nil)
        #expect(today.blocked == .leadTime)

        let tomorrow = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(dueDay: day(1)), context: context, dismissedAt: nil
        )
        #expect(tomorrow.proposal?.displayedMinute == 600, "only today-due tasks race the clock")
    }

    @Test("lapsed silences everything, however rich the data")
    func lapsed() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(),
            context: makeContext(global: dist(cluster(25, minute: 600)), isLapsed: true),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .lapsed)
    }

    @Test("apple-sourced tasks get no chip (defensive - the editor never opens them)")
    func appleSource() {
        let result = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(isAppleSource: true),
            context: makeContext(global: dist(cluster(25, minute: 600))),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .apple)
    }

    @Test("preconditions not held: no date, or a time already chosen, is an empty evaluation")
    func preconditions() {
        let context = makeContext(global: dist(cluster(15, minute: 600)))
        let noDate = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(dueDay: nil), context: context, dismissedAt: nil
        )
        #expect(noDate.proposal == nil && noDate.blocked == nil)

        let hasTime = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(hasTime: true, scheduledMinute: 540), context: context, dismissedAt: nil
        )
        #expect(hasTime.proposal == nil && hasTime.blocked == nil)
    }
}

// MARK: - Dismissal re-arm (on the DISPLAYED proposal)

@Suite("Suggestions · dismissal")
struct SuggestionDismissalTests {

    @Test("a dismissed displayed minute stays hidden until it moves 60 displayed minutes")
    func rearm() {
        let context = makeContext(global: dist(cluster(15, minute: 600)))
        let hidden = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(), context: context, dismissedAt: 600
        )
        #expect(hidden.proposal == nil)
        #expect(hidden.blocked == .dismissed)

        // An internal drift that still displays inside the re-arm distance
        // changed nothing for the user.
        let nearby = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(), context: context, dismissedAt: 630
        )
        #expect(nearby.proposal == nil)
        #expect(nearby.blocked == .dismissed)

        let moved = SuggestionEngine.evaluateNewTime(
            task: makeSnapshot(), context: context, dismissedAt: 540
        )
        #expect(moved.proposal != nil, ">= 60 displayed minutes re-arms")
    }
}

// MARK: - Re-time

@Suite("Suggestions · re-time")
struct SuggestionReTimeTests {

    private func seriesDist(_ count: Int = 8, minute: Int = 1200) -> DistributionResult {
        dist(cluster(count, minute: minute, identityPrefix: "s"), scope: .series("s1"))
    }

    @Test("a series completed nightly at 20:00 but scheduled 09:00 offers the change")
    func fires() {
        let result = SuggestionEngine.evaluateReTime(
            task: makeSnapshot(isRecurring: true, hasTime: true, scheduledMinute: 540),
            context: makeContext(series: seriesDist()),
            dismissedAt: nil
        )
        let proposal = try! #require(result.proposal)
        #expect(proposal.trigger == .reTime)
        #expect(proposal.tier == .series)
        #expect(proposal.displayedMinute == 1200)
    }

    @Test("mismatch is measured on the UNROUNDED peak and wraps midnight")
    func mismatchWraps() {
        // Peak 21:00, scheduled 09:00: circular distance 12h >= 3h.
        let wrapped = SuggestionEngine.evaluateReTime(
            task: makeSnapshot(isRecurring: true, hasTime: true, scheduledMinute: 540),
            context: makeContext(series: seriesDist(minute: 1260)),
            dismissedAt: nil
        )
        #expect(wrapped.proposal != nil)

        // Peak 20:00, scheduled 19:00: one hour of drift is not a
        // scheduling problem.
        let close = SuggestionEngine.evaluateReTime(
            task: makeSnapshot(isRecurring: true, hasTime: true, scheduledMinute: 1140),
            context: makeContext(series: seriesDist()),
            dismissedAt: nil
        )
        #expect(close.proposal == nil)
        #expect(close.blocked == .mismatch)
    }

    @Test("series floor: seven timed completions do not justify moving a due time")
    func seriesFloor() {
        let result = SuggestionEngine.evaluateReTime(
            task: makeSnapshot(isRecurring: true, hasTime: true, scheduledMinute: 540),
            context: makeContext(series: seriesDist(7)),
            dismissedAt: nil
        )
        #expect(result.proposal == nil)
        #expect(result.blocked == .evidence)
    }

    @Test("one-off tasks never get re-time - there is no future series to change")
    func oneOffExcluded() {
        let result = SuggestionEngine.evaluateReTime(
            task: makeSnapshot(isRecurring: false, hasTime: true, scheduledMinute: 540),
            context: makeContext(series: seriesDist()),
            dismissedAt: nil
        )
        #expect(result.proposal == nil && result.blocked == nil)
    }

    @Test("no series distribution means no re-time, however rich list/global data is")
    func noSeriesNoReTime() {
        let result = SuggestionEngine.evaluateReTime(
            task: makeSnapshot(isRecurring: true, hasTime: true, scheduledMinute: 540),
            context: makeContext(series: nil, global: dist(cluster(30, minute: 1200))),
            dismissedAt: nil
        )
        #expect(result.proposal == nil && result.blocked == nil)
    }
}
