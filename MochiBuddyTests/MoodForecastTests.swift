//
//  MoodForecastTests.swift
//  MochiBuddyTests
//
//  mood(t) is the notification system's foundation: one deterministic
//  curve, evaluated at schedule time and on open, agreeing by
//  construction. These tests pin the simulation of every app-closed
//  event: due-crossings, recurrence rolls, momentum aging, buffer decay,
//  vacation auto-expiry, and the entitlement horizon cap.
//
//  Dates.now anchor: Wed 8 Jul 2026, 10:00 local.
//

import Foundation
import Testing
@testable import MochiBuddy

private func makeSnapshot(
    tasks: [TaskItem] = [],
    completionTimes: [Date] = [],
    boosts: [BufferBoost] = [],
    vacationMode: Bool = false,
    vacationResumeAt: Date? = nil,
    entitlementExpiry: Date? = nil,
    capturedAt: Date = Dates.now
) -> MoodSnapshot {
    MoodSnapshot(
        tasks: tasks, completionTimes: completionTimes, boosts: boosts,
        vacationMode: vacationMode, vacationResumeAt: vacationResumeAt,
        entitlementExpiry: entitlementExpiry, capturedAt: capturedAt
    )
}

private let anchor = MoodEngine.Constants.anchor // 58, the content resting value

@Suite("MoodBand")
struct MoodBandTests {

    @Test("the six bands split 0-100 at the design doc's thresholds")
    func bandThresholds() {
        #expect(MoodBand(value: 0) == .verySad)
        #expect(MoodBand(value: 14.9) == .verySad)
        #expect(MoodBand(value: 15) == .anxious)
        #expect(MoodBand(value: 34.9) == .anxious)
        #expect(MoodBand(value: 35) == .uneasy)
        #expect(MoodBand(value: 49.9) == .uneasy)
        #expect(MoodBand(value: 50) == .content)
        #expect(MoodBand(value: 69.9) == .content)
        #expect(MoodBand(value: 70) == .happy)
        #expect(MoodBand(value: 87.9) == .happy)
        #expect(MoodBand(value: 88) == .ecstatic)
        #expect(MoodBand(value: 100) == .ecstatic)
    }

    @Test("bands order from very sad up to ecstatic")
    func bandOrdering() {
        #expect(MoodBand.verySad < .anxious)
        #expect(MoodBand.anxious < .uneasy)
        #expect(MoodBand.uneasy < .content)
        #expect(MoodBand.content < .happy)
        #expect(MoodBand.happy < .ecstatic)
    }
}

@Suite("VacationSchedule")
struct VacationScheduleTests {

    @Test("off is off, open-ended stays on, fixed-date expires at the instant")
    func expiryRule() {
        #expect(!VacationSchedule.isActive(mode: false, resumeAt: nil, at: Dates.now))
        #expect(VacationSchedule.isActive(mode: true, resumeAt: nil, at: Dates.now))
        #expect(VacationSchedule.isActive(mode: true, resumeAt: Dates.hours(1), at: Dates.now))
        #expect(!VacationSchedule.isActive(mode: true, resumeAt: Dates.now, at: Dates.now))
        #expect(!VacationSchedule.isActive(mode: true, resumeAt: Dates.hours(-1), at: Dates.now))
    }

    @Test("the profile helper applies the same rule")
    func profileHelper() {
        var profile = makeProfile(vacationMode: true)
        profile.vacationResumeAt = Dates.hours(-1)
        #expect(!profile.vacationActive(at: Dates.now), "expired vacation must read as over")
        profile.vacationResumeAt = Dates.hours(1)
        #expect(profile.vacationActive(at: Dates.now))
    }
}

@Suite("MoodForecast · the invariant seed")
struct MoodForecastEquivalenceTests {

    @Test("forecast at capture time IS the live engine - same tasks, same momentum, same buffer")
    func nowEquivalence() {
        let tasks = [
            makeTask(dueAt: Dates.hours(-5), hasTime: true, priority: .high),
            makeTask(dueAt: Dates.days(2)),
            makeTask(), // undated - never stresses
        ]
        let completions = [Dates.hours(-2), Dates.hours(-20)]
        let boost = BufferBoost(lift: 8, startedAt: Dates.hours(-0.1), duration: 15 * 60)
        let snapshot = makeSnapshot(tasks: tasks, completionTimes: completions, boosts: [boost])

        let engineBaseline = MoodEngine.baseline(
            incompleteTasks: tasks, completionsLast24h: 2, vacationMode: false, now: Dates.now
        )
        let expected = min(100, max(0, engineBaseline + boost.value(at: Dates.now)))

        #expect(MoodForecast.baseline(at: Dates.now, snapshot: snapshot) == engineBaseline)
        #expect(MoodForecast.displayed(at: Dates.now, snapshot: snapshot) == expected)
    }
}

@Suite("MoodForecast · due-crossings")
struct MoodForecastDueCrossingTests {

    @Test("a future timed task stresses the curve only after its instant, one crossing found there")
    func futureDueCrossing() {
        let due = Dates.hours(2)
        let snapshot = makeSnapshot(tasks: [makeTask(dueAt: due, hasTime: true, priority: .high)])

        let curve = MoodForecast.curve(until: Dates.hours(8), snapshot: snapshot)
        for sample in curve where sample.date <= due {
            #expect(sample.value == anchor, "no stress before the due instant")
        }

        let crossings = MoodForecast.bandCrossings(until: Dates.hours(8), snapshot: snapshot)
        #expect(crossings.count == 1)
        #expect(crossings.first?.from == .content)
        #expect(crossings.first?.to == .uneasy, "the BASE sting alone drops one high task below 50")
        if let date = crossings.first?.date {
            #expect(abs(date.timeIntervalSince(due)) <= 120, "crossing located at the due instant")
        }
    }

    @Test("a date-only task flips at the end of its local day, not at a stored clock time")
    func dateOnlyFlipsAtMidnight() {
        let snapshot = makeSnapshot(tasks: [makeTask(dueAt: Dates.startOfToday)])
        let midnight = Dates.calendar.date(byAdding: .day, value: 1, to: Dates.startOfToday)!

        let crossings = MoodForecast.bandCrossings(until: Dates.days(2), snapshot: snapshot)
        #expect(crossings.count == 1)
        #expect(crossings.first?.to == .uneasy)
        if let date = crossings.first?.date {
            #expect(abs(date.timeIntervalSince(midnight)) <= 120)
        }
    }

    @Test("dormant user: the no-action curve never rises and visits each band at most once")
    func dormantCurveIsMonotone() {
        let tasks = [
            makeTask(dueAt: Dates.hours(1), hasTime: true, priority: .high),
            makeTask(dueAt: Dates.hours(6), hasTime: true, priority: .high),
            makeTask(dueAt: Dates.hours(12), hasTime: true),
            makeTask(dueAt: Dates.hours(24), hasTime: true, priority: .high),
            makeTask(dueAt: Dates.hours(30), hasTime: true, priority: .high),
        ]
        let snapshot = makeSnapshot(tasks: tasks)

        let curve = MoodForecast.curve(until: Dates.days(4), snapshot: snapshot)
        for (previous, next) in zip(curve, curve.dropFirst()) {
            #expect(next.value <= previous.value + 1e-9, "no-action forecast must never rise")
        }

        let crossings = MoodForecast.bandCrossings(until: Dates.days(4), snapshot: snapshot)
        #expect(crossings.map(\.to) == [.uneasy, .anxious, .verySad],
                "each band boundary crossed exactly once, in descending order")
        let dates = crossings.map(\.date)
        #expect(dates == dates.sorted())
    }

    @Test("a discontinuous plunge (many tasks due at once) reports one jump, not phantom intermediate bands")
    func plungeIsOneJump() {
        // Ten high tasks at the same instant: the BASE sting lands 58 → ~8
        // with no time spent in between - one crossing, content → verySad.
        let due = Dates.hours(1)
        let tasks = (0..<10).map { i in
            makeTask(id: "t\(i)", dueAt: due, hasTime: true, priority: .high)
        }
        let snapshot = makeSnapshot(tasks: tasks)

        let crossings = MoodForecast.bandCrossings(until: Dates.hours(6), snapshot: snapshot)
        #expect(crossings.count == 1)
        #expect(crossings.first?.from == .content)
        #expect(crossings.first?.to == .verySad)
    }

    @Test("two staggered drops inside one sampling step are both found, in order")
    func staggeredDropsWithinOneStep() {
        // Five high tasks at +60min (→ anxious), five more at +65min
        // (→ very sad): both crossings sit inside a single 15-min step.
        let firstDue = Dates.hours(1)
        let secondDue = firstDue.addingTimeInterval(5 * 60)
        var tasks = (0..<5).map { i in
            makeTask(id: "a\(i)", dueAt: firstDue, hasTime: true, priority: .high)
        }
        tasks += (0..<5).map { i in
            makeTask(id: "b\(i)", dueAt: secondDue, hasTime: true, priority: .high)
        }
        let snapshot = makeSnapshot(tasks: tasks)

        let crossings = MoodForecast.bandCrossings(until: Dates.hours(6), snapshot: snapshot)
        #expect(crossings.map(\.from) == [.content, .anxious])
        #expect(crossings.map(\.to) == [.anxious, .verySad])
        if crossings.count == 2 {
            #expect(abs(crossings[0].date.timeIntervalSince(firstDue)) <= 120)
            #expect(abs(crossings[1].date.timeIntervalSince(secondDue)) <= 120)
        }
    }
}

@Suite("MoodForecast · recurrence")
struct MoodForecastRecurrenceTests {

    @Test("a recurring task's future stress is evaluated on its rolled-forward due date")
    func rollForwardIsSimulated() {
        // Daily 9:00 habit, one hour late at capture. Two days out the
        // forecast must judge it against THAT day's 9:00, exactly as the
        // roller would re-stamp it on open.
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)
        )!
        let habit = makeTask(id: "habit", dueAt: due, hasTime: true, priority: .high, repeatRule: .daily)
        let snapshot = makeSnapshot(tasks: [habit])

        let friday10 = Dates.days(2) // Fri 10 Jul, 10:00
        let fridayDue = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 10, hour: 9)
        )!
        let expected = MoodEngine.baseline(
            incompleteTasks: [makeTask(id: "habit", dueAt: fridayDue, hasTime: true, priority: .high, repeatRule: .daily)],
            completionsLast24h: 0, vacationMode: false, now: friday10
        )
        #expect(MoodForecast.baseline(at: friday10, snapshot: snapshot) == expected)
    }

    @Test("a neglected daily habit is a bounded hum, not a snowball - same value at the same clock time")
    func neglectedHabitIsBounded() {
        let due = Dates.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)
        )!
        let habit = makeTask(id: "habit", dueAt: due, hasTime: true, priority: .high, repeatRule: .daily)
        let snapshot = makeSnapshot(tasks: [habit])

        let thursday = MoodForecast.baseline(at: Dates.days(1), snapshot: snapshot)
        let saturday = MoodForecast.baseline(at: Dates.days(3), snapshot: snapshot)
        #expect(abs(thursday - saturday) < 1e-9, "steady state: lateness re-caps every roll")
        #expect(thursday < anchor, "still present - one hour late every day")
    }
}

@Suite("MoodForecast · momentum & buffer")
struct MoodForecastDecayTests {

    @Test("momentum ages out: a lone completion stops lifting 24h after it happened")
    func momentumAgesOut() {
        let completedAt = Dates.hours(-20)
        let snapshot = makeSnapshot(completionTimes: [completedAt])

        #expect(MoodForecast.band(at: Dates.now, snapshot: snapshot) == .happy)

        let crossings = MoodForecast.bandCrossings(until: Dates.hours(12), snapshot: snapshot)
        #expect(crossings.count == 1)
        #expect(crossings.first?.from == .happy)
        #expect(crossings.first?.to == .content)
        if let date = crossings.first?.date {
            let expiry = completedAt.addingTimeInterval(MoodForecast.momentumWindow)
            #expect(abs(date.timeIntervalSince(expiry)) <= 120)
        }
    }

    @Test("buffer decay is the store's own linear math, point for point")
    func bufferDecayExact() {
        let boost = BufferBoost(lift: 20, startedAt: Dates.now, duration: 2 * 3600)
        let snapshot = makeSnapshot(boosts: [boost])

        for offset in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0] {
            let t = Dates.hours(offset)
            #expect(MoodForecast.displayed(at: t, snapshot: snapshot) == anchor + boost.value(at: t))
        }
        // 58+20 → happy; falls below 70 when the lift decays to 12 (48 min in).
        let crossings = MoodForecast.bandCrossings(until: Dates.hours(4), snapshot: snapshot)
        #expect(crossings.count == 1)
        #expect(crossings.first?.from == .happy)
        #expect(crossings.first?.to == .content)
        if let date = crossings.first?.date {
            #expect(abs(date.timeIntervalSince(Dates.hours(0.8))) <= 120)
        }
    }

    @Test("stacked boosts clamp to the +30 cap, exactly like the store")
    func bufferClampsAtCap() {
        let snapshot = makeSnapshot(boosts: [
            BufferBoost(lift: 20, startedAt: Dates.now, duration: 6 * 3600),
            BufferBoost(lift: 20, startedAt: Dates.now, duration: 6 * 3600),
        ])
        #expect(MoodForecast.displayed(at: Dates.now, snapshot: snapshot) == anchor + MoodEngine.Constants.bufferCap)
        #expect(MoodForecast.band(at: Dates.now, snapshot: snapshot) == .ecstatic)
    }
}

@Suite("MoodForecast · vacation & horizon")
struct MoodForecastHorizonTests {

    @Test("vacation holds the curve at content until auto-expiry, then stress resumes")
    func vacationSuppressesUntilResume() {
        let resumeAt = Dates.days(2)
        let snapshot = makeSnapshot(
            tasks: [makeTask(dueAt: Dates.hours(-10), hasTime: true, priority: .high)],
            vacationMode: true,
            vacationResumeAt: resumeAt
        )

        let curve = MoodForecast.curve(until: Dates.days(3), snapshot: snapshot)
        for sample in curve where sample.date < resumeAt {
            #expect(sample.value == anchor, "truly quiet: no stress accrues while away")
        }

        let crossings = MoodForecast.bandCrossings(until: Dates.days(3), snapshot: snapshot)
        #expect(crossings.count == 1)
        #expect(crossings.first?.from == .content)
        #expect(crossings.first?.to == .uneasy)
        if let date = crossings.first?.date {
            #expect(abs(date.timeIntervalSince(resumeAt)) <= 120)
        }
    }

    @Test("open-ended vacation forecasts flat forever - no crossings to schedule against")
    func openEndedVacationIsFlat() {
        let snapshot = makeSnapshot(
            tasks: [makeTask(dueAt: Dates.hours(-10), hasTime: true, priority: .high)],
            vacationMode: true
        )
        let curve = MoodForecast.curve(until: Dates.days(7), snapshot: snapshot)
        #expect(curve.allSatisfy { $0.value == anchor })
        #expect(MoodForecast.bandCrossings(until: Dates.days(7), snapshot: snapshot).isEmpty)
    }

    @Test("the horizon is hard-capped at entitlement expiry - nothing is forecast into lapsed")
    func entitlementCapsHorizon() {
        let expiry = Dates.days(1)
        let snapshot = makeSnapshot(
            tasks: [makeTask(dueAt: Dates.hours(36), hasTime: true, priority: .high)],
            entitlementExpiry: expiry
        )

        let curve = MoodForecast.curve(until: Dates.days(3), snapshot: snapshot)
        #expect(curve.last?.date == expiry)
        #expect(MoodForecast.bandCrossings(until: Dates.days(3), snapshot: snapshot).isEmpty,
                "the due-crossing at +36h lies beyond the horizon")
    }

    @Test("an empty or inverted horizon yields nothing rather than a degenerate curve")
    func degenerateHorizon() {
        let snapshot = makeSnapshot(entitlementExpiry: Dates.hours(-1))
        #expect(MoodForecast.curve(until: Dates.days(1), snapshot: snapshot).isEmpty)
        #expect(MoodForecast.bandCrossings(until: Dates.days(1), snapshot: snapshot).isEmpty)
    }
}

@Suite("MoodForecast · crossing self-consistency")
struct MoodForecastConsistencyTests {

    @Test("every reported crossing agrees with re-evaluating the curve at that instant")
    func crossingsMatchReevaluation() {
        let tasks = [
            makeTask(dueAt: Dates.hours(3), hasTime: true, priority: .high),
            makeTask(dueAt: Dates.hours(20), hasTime: true),
            makeTask(dueAt: Dates.startOfToday),
        ]
        let snapshot = makeSnapshot(
            tasks: tasks,
            completionTimes: [Dates.hours(-22)],
            boosts: [BufferBoost(lift: 15, startedAt: Dates.now, duration: 3600)]
        )

        let crossings = MoodForecast.bandCrossings(until: Dates.days(3), snapshot: snapshot)
        #expect(!crossings.isEmpty)
        for crossing in crossings {
            #expect(MoodForecast.band(at: crossing.date, snapshot: snapshot) == crossing.to,
                    "the baked-in band must equal mood(fireTime) recomputed")
        }
    }
}
