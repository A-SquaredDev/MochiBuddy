//
//  ObservationLedgerTests.swift
//  MochiBuddyTests
//
//  The ledger owns surfacing cadence ONLY - nothing in it can change a
//  conclusion. Per-UID isolation, the version gate, caps, dedup, cooldown,
//  copy rotation; plus the interval log's append/close discipline and the
//  recorder's transition/reconcile behavior.
//

import Foundation
import Testing
@testable import MochiBuddy

private func freshDefaults() -> UserDefaults {
    let name = "obs-ledger-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func qualifiedWeekday(_ weekday: Int = 3) -> QualifiedObservation {
    QualifiedObservation(kind: .weekday, conclusion: .weekday(weekday), stableSince: "2026-06-20")
}

@Suite("Observations · ledger")
@MainActor
struct ObservationLedgerTests {

    @Test("cadence state is namespaced per UID - no inherited or leaked state")
    func perUIDIsolation() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        ledger.recordSurfaced(qualifiedWeekday(), surface: .rundown, on: "2026-07-08", userId: "user1")

        #expect(!ledger.canSurfaceInRundown(qualifiedWeekday(), on: "2026-07-08", userId: "user1"),
                "same week, same conclusion: deduped for user1")
        #expect(ledger.canSurfaceInRundown(qualifiedWeekday(), on: "2026-07-08", userId: "user2"),
                "a different account starts a fresh cadence")

        ledger.clear(userId: "user1")
        #expect(ledger.canSurfaceInRundown(qualifiedWeekday(), on: "2026-07-08", userId: "user1"),
                "deletion clears the UID's keys")
    }

    @Test("the weekly rundown cap and same-week dedup hold; a new week resets")
    func rundownCapAndDedup() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        let userId = "user1"
        let monday = "2026-07-06"

        ledger.recordSurfaced(qualifiedWeekday(3), surface: .rundown, on: monday, userId: userId)
        #expect(!ledger.canSurfaceInRundown(qualifiedWeekday(3), on: "2026-07-08", userId: userId),
                "the same conclusion never repeats within a week")

        let band = QualifiedObservation(kind: .timeOfDay, conclusion: .band(.morning), stableSince: "2026-06-01")
        #expect(ledger.canSurfaceInRundown(band, on: "2026-07-08", userId: userId))
        ledger.recordSurfaced(band, surface: .rundown, on: "2026-07-08", userId: userId)

        let comeback = QualifiedObservation(kind: .comeback, conclusion: .comeback, stableSince: "2026-06-01")
        #expect(!ledger.canSurfaceInRundown(comeback, on: "2026-07-09", userId: userId),
                "two observations per week is the rundown cap")
        #expect(ledger.canSurfaceInRundown(comeback, on: "2026-07-13", userId: userId),
                "the following week starts fresh")
    }

    @Test("a conclusion a rundown told this week stays out of the letter, and vice versa")
    func crossSurfaceDedup() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        ledger.recordSurfaced(qualifiedWeekday(), surface: .rundown, on: "2026-07-07", userId: "u")
        #expect(!ledger.canSurfaceInLetter(qualifiedWeekday(), on: "2026-07-09", userId: "u"),
                "hearing it twice in two days reads as a script")

        let other = QualifiedObservation(kind: .comeback, conclusion: .comeback, stableSince: "2026-06-01")
        ledger.recordSurfaced(other, surface: .letter, on: "2026-07-09", userId: "u")
        #expect(!ledger.canSurfaceInRundown(other, on: "2026-07-10", userId: "u"))
    }

    @Test("the Journal is ambient: surfacing there never consumes weekly cadence")
    func journalDoesNotConsume() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        ledger.recordSurfaced(qualifiedWeekday(), surface: .journal, on: "2026-07-07", userId: "u")
        #expect(ledger.canSurfaceInRundown(qualifiedWeekday(), on: "2026-07-08", userId: "u"))
    }

    @Test("list return never takes a rundown line, and its event surfaces once")
    func listReturnRules() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        let event = QualifiedObservation(
            kind: .listReturn, conclusion: .listReturn(listId: "personal"), stableSince: "2026-07-06"
        )
        #expect(!ledger.canSurfaceInRundown(event, on: "2026-07-08", userId: "u"),
                "its surfaces are letter beats and the Journal, never the rundown")
        #expect(ledger.canSurfaceInLetter(event, on: "2026-07-08", userId: "u"))
        ledger.recordSurfaced(event, surface: .letter, on: "2026-07-08", userId: "u")
        #expect(!ledger.canSurfaceInLetter(event, on: "2026-07-20", userId: "u"),
                "an event tells once, then expires")
    }

    @Test("momentum honors its cooldown after surfacing")
    func momentumCooldown() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        let momentum = QualifiedObservation(kind: .momentum, conclusion: .momentumRising, stableSince: "2026-07-01")
        ledger.recordSurfaced(momentum, surface: .rundown, on: "2026-07-01", userId: "u")

        #expect(!ledger.canSurfaceInRundown(momentum, on: "2026-07-07", userId: "u"),
                "6 days later: still cooling down (and same-week dedup aside)")
        #expect(ledger.canSurfaceInRundown(momentum, on: "2026-07-09", userId: "u"),
                "8 days later, new week: eligible again")
    }

    @Test("lastSurfacedDay reports the surfacing day - the Journal card's day-of guard")
    func lastSurfacedDayHelper() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        let momentum = QualifiedObservation(kind: .momentum, conclusion: .momentumRising, stableSince: "2026-07-01")
        #expect(ledger.lastSurfacedDay(of: .momentumRising, userId: "u") == nil)

        ledger.recordSurfaced(momentum, surface: .journal, on: "2026-07-01", userId: "u")
        #expect(ledger.lastSurfacedDay(of: .momentumRising, userId: "u") == "2026-07-01")

        // The Journal card must NOT re-record on later cooldown days -
        // that would roll this date forward daily and keep momentum out
        // of rundowns and letters forever. The card's guard reads this
        // value and peeks instead of surfacing.
        let day = CivilDay("2026-07-03")!
        #expect(ledger.momentumCoolingDown(on: day, userId: "u"))
        #expect(ledger.lastSurfacedDay(of: .momentumRising, userId: "u") == "2026-07-01",
                "still the original day: nothing but recordSurfaced may advance it")
    }

    @Test("observation_evaluated logs at most once per type per civil day")
    func evaluationThrottle() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        #expect(ledger.shouldLogEvaluation(kind: .weekday, day: "2026-07-08", userId: "u"))
        #expect(!ledger.shouldLogEvaluation(kind: .weekday, day: "2026-07-08", userId: "u"))
        #expect(ledger.shouldLogEvaluation(kind: .momentum, day: "2026-07-08", userId: "u"),
                "the cap is per type")
        #expect(ledger.shouldLogEvaluation(kind: .weekday, day: "2026-07-09", userId: "u"))
    }

    @Test("a semantic version mismatch clears surfacing state wholesale")
    func versionGate() {
        let defaults = freshDefaults()
        let ledger = ObservationLedger(defaults: defaults)
        ledger.recordSurfaced(qualifiedWeekday(), surface: .rundown, on: "2026-07-08", userId: "u")

        var stale = ledger.state(userId: "u")
        stale.algorithmVersion = ObservationConstants.algorithmVersion - 1
        defaults.set(try? JSONEncoder().encode(stale), forKey: "mochi.observations.ledger.u")

        #expect(ledger.state(userId: "u") == ObservationLedger.State(),
                "conclusions may have changed meaning; cadence resets")
    }

    @Test("copy rotation never repeats until the pool cycles, and lines carry no numbers")
    func copyRotation() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        var seen: Set<String> = []
        for _ in 0..<ObservationCopy.weekdayPool.count {
            let line = ledger.nextLine(for: .weekday(3), petName: "Nori", userId: "u")!
            #expect(line.contains("Tuesdays"))
            #expect(line.contains("Nori"))
            #expect(!line.contains("{name}") && !line.contains("{weekday}"))
            seen.insert(line)
        }
        #expect(seen.count == ObservationCopy.weekdayPool.count, "full cycle before any repeat")
    }

    @Test("a list-return line without a surviving list name yields nil, never broken copy")
    func listReturnLineNeedsName() {
        let ledger = ObservationLedger(defaults: freshDefaults())
        #expect(ledger.nextLine(for: .listReturn(listId: "x"), petName: "Nori", userId: "u") == nil)
        let line = ledger.nextLine(
            for: .listReturn(listId: "x"), petName: "Nori", listName: "Personal", userId: "u"
        )
        #expect(line?.contains("Personal") == true)
    }

    @Test("every observation copy line passes the house style: no em dashes, no digits, no emoji")
    func copyStyle() {
        let pools = [
            ObservationCopy.weekdayPool, ObservationCopy.morningPool,
            ObservationCopy.afternoonPool, ObservationCopy.eveningPool,
            ObservationCopy.nightPool, ObservationCopy.momentumPool,
            ObservationCopy.listReturnPool, ObservationCopy.comebackPool,
        ]
        for line in pools.joined() {
            #expect(!line.contains("\u{2014}"), "no em dashes, ever: \(line)")
            #expect(line.unicodeScalars.allSatisfy { $0.properties.isEmoji == false || $0.isASCII },
                    "no emoji in observation copy: \(line)")
            // "after 9pm" is the one sanctioned time phrase (a band edge,
            // not a measurement); nothing else may quantify.
            let stripped = line.replacingOccurrences(of: "9pm", with: "")
            let hasNumber = stripped.contains { $0.isNumber }
            #expect(!hasNumber, "observation copy is qualitative by locked rule: \(line)")
        }
    }
}

// MARK: - Interval log

@Suite("Observations · interval log")
struct ObservationIntervalTests {

    @Test("append opens at most one interval per kind; close ends the open one")
    func appendCloseDiscipline() {
        var log: [ObservationInterval] = []
        log = log.appending(open: .vacation, at: Dates.now)
        log = log.appending(open: .vacation, at: Dates.hours(1))
        #expect(log.count == 1, "a second open is a no-op")

        log = log.appending(open: .lapse, at: Dates.hours(2))
        #expect(log.count == 2, "kinds are independent")

        log = log.closing(.vacation, at: Dates.days(3))
        #expect(log.openInterval(.vacation) == nil)
        #expect(log.openInterval(.lapse) != nil)
        #expect(log[0].end == Dates.days(3))

        log = log.closing(.vacation, at: Dates.days(4))
        #expect(log[0].end == Dates.days(3), "closing again touches nothing")
    }

    @Test("a close before the open degrades to zero length, never negative")
    func clockSkewClamp() {
        var log: [ObservationInterval] = []
        log = log.appending(open: .lapse, at: Dates.now)
        log = log.closing(.lapse, at: Dates.hours(-5))
        #expect(log[0].end == log[0].start)
    }
}

// MARK: - Interval recorder

@Suite("Observations · interval recorder")
@MainActor
struct ObservationIntervalRecorderTests {

    private func makeRecorder(
        profile: UserProfile
    ) -> (ObservationIntervalRecorder, StubProfileRepository) {
        let profileRepo = StubProfileRepository()
        profileRepo.profile = profile
        let recorder = ObservationIntervalRecorder(
            authRepository: StubAuthRepository(), profileRepository: profileRepo
        )
        return (recorder, profileRepo)
    }

    @Test("vacation start and end append and close the synced log")
    func vacationLifecycle() async {
        let (recorder, repo) = makeRecorder(profile: makeProfile())
        await recorder.vacationStarted(at: Dates.now)
        #expect(repo.profile?.observationIntervals.openInterval(.vacation)?.start == Dates.now)

        // The re-entry service passes the TRUE end - a trip that expired
        // days ago closes at its scheduled end, not at open time.
        await recorder.vacationEnded(at: Dates.days(5))
        #expect(repo.profile?.observationIntervals == [
            ObservationInterval(kind: .vacation, start: Dates.now, end: Dates.days(5)),
        ])
    }

    @Test("membership transitions open and close the lapse interval exactly once")
    func lapseTransitions() async {
        let (recorder, repo) = makeRecorder(profile: makeProfile())
        await recorder.membershipChanged(isLapsed: true, at: Dates.now)
        await recorder.membershipChanged(isLapsed: true, at: Dates.hours(1))
        #expect(repo.savedIntervalLogs.count == 1, "a repeat status is a no-op write")

        await recorder.membershipChanged(isLapsed: false, at: Dates.days(2))
        #expect(repo.profile?.observationIntervals == [
            ObservationInterval(kind: .lapse, start: Dates.now, end: Dates.days(2)),
        ])
    }

    @Test("reconcile stamps the log start once and realigns missed transitions")
    func reconcileBackstop() async {
        // A vacation entered on another device (profile says active, log
        // never heard) and a log that has never been stamped.
        let (recorder, repo) = makeRecorder(profile: makeProfile(
            vacationMode: true, vacationStartedAt: Dates.days(-3)
        ))
        await recorder.reconcile(isLapsed: false, now: Dates.now)

        #expect(repo.stampedLogSinces == [Dates.now], "the honest-fallback anchor")
        #expect(repo.profile?.observationIntervals.openInterval(.vacation)?.start == Dates.days(-3))

        await recorder.reconcile(isLapsed: false, now: Dates.hours(1))
        #expect(repo.stampedLogSinces.count == 1, "set-once")
    }

    @Test("reconcile closes a vacation interval whose end no hook witnessed")
    func reconcileClosesStaleVacation() async {
        // The log holds an open vacation, but the profile's vacation is
        // over (ended by cap while the app was gone; re-entry ran on
        // another device). Close at the best attested boundary.
        let start = Dates.days(-10)
        let (recorder, repo) = makeRecorder(profile: makeProfile(
            observationIntervals: [ObservationInterval(kind: .vacation, start: start, end: nil)],
            observationLogSince: Dates.days(-30)
        ))
        await recorder.reconcile(isLapsed: false, now: Dates.now)
        let closed = repo.profile?.observationIntervals.first
        #expect(closed?.end != nil)
        #expect(closed!.end! <= Dates.now)
    }
}
