//
//  LetterCompositionServiceTests.swift
//  MochiBuddyTests
//
//  The letter lifecycle (Personal Layer, Feature 3): gating (first-period
//  / dormant / vacation / lapse, never a backfill), the online barrier's
//  sequencing, first-writer-wins, the engagement marker's semantics, and
//  the planner's scheduling invariant. Fixture anchor: Dates.now = Wed
//  Jul 8 2026; the previous closed period is the Jun 29 week.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private struct Harness {
    let service: LetterCompositionService
    let letterRepo: StubLetterRepository
    let profileRepo: StubProfileRepository
    let taskRepo: StubTaskRepository
    let membership: MembershipSession
    let telemetry: RecordingLetterTelemetry

    /// A profile whose adoption long predates the window, pinned to the
    /// machine zone so period math in tests and service agree.
    init(profile: UserProfile? = nil) {
        let profileRepo = StubProfileRepository()
        var base = profile ?? makeProfile(adoptedOn: "2026-05-01")
        base.timezone = TimeZone.current.identifier
        profileRepo.profile = base

        let letterRepo = StubLetterRepository()
        let taskRepo = StubTaskRepository()
        let membership = MembershipSession()
        let telemetry = RecordingLetterTelemetry()
        service = LetterCompositionService(
            authRepository: StubAuthRepository(),
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            listRepository: StubListRepository(),
            letterRepository: letterRepo,
            observationLedger: ObservationLedger(defaults: {
                let name = "letter-tests-\(UUID().uuidString)"
                return UserDefaults(suiteName: name)!
            }()),
            membershipSession: membership,
            relay: nil,
            telemetry: telemetry
        )
        self.letterRepo = letterRepo
        self.profileRepo = profileRepo
        self.taskRepo = taskRepo
        self.membership = membership
        self.telemetry = telemetry
    }

    /// Seeds completions inside the previous closed period (Jun 29 week).
    func seedPreviousPeriodCompletions(_ count: Int = 5) {
        taskRepo.completedStats = (0..<count).map { index in
            makeStat(
                localDate: CivilDay(of: Dates.days(-5 - index % 3), in: .current).dateString,
                localMinute: 600,
                completedAt: Dates.days(-5 - index % 3)
            )
        }
    }
}

@Suite("Letters · composition service")
@MainActor
struct LetterCompositionServiceTests {

    @Test("an engaged previous period composes exactly one letter, unread")
    func composes() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)

        #expect(harness.letterRepo.stored.count == 1)
        let letter = harness.letterRepo.stored[0]
        #expect(letter.id.hasPrefix("letter-2026-06-29"))
        #expect(letter.petNameSnapshot == "Mochi")
        #expect(letter.readAt == nil)
        #expect(letter.composerVersion == LetterConstants.composerVersion)
        #expect(harness.service.unreadLetter == letter)
        #expect(harness.telemetry.events.contains {
            if case .composed = $0 { return true } else { return false }
        })
    }

    @Test("the archive existence check runs once per period, not every foreground")
    func archiveCheckMemoized() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.count == 1)

        let fetchesAfterCompose = harness.letterRepo.archiveFetches
        await harness.service.handleUserForeground(now: Dates.hours(2))
        await harness.service.handleUserForeground(now: Dates.hours(4))
        #expect(harness.letterRepo.archiveFetches == fetchesAfterCompose + 2,
                "each foreground pays exactly ONE archive read (the unread-envelope refresh, by design) and never a second for the existence check")
        #expect(harness.letterRepo.stored.count == 1, "and still exactly one letter")
    }

    @Test("the current period's engagement marker is stamped on foreground")
    func marksEngagement() async {
        let harness = Harness()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.markers.contains("letter-2026-07-06"),
                "Jul 8 sits in the Jul 6 period")
    }

    @Test("dormant period: zero completions and no marker - silence, no backfill")
    func dormantSkips() async {
        let harness = Harness()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.isEmpty,
                "no letter, no notification, no 'we missed you'")
    }

    @Test("a quiet-but-present period composes: the marker alone qualifies")
    func markerAloneQualifies() async {
        let harness = Harness()
        harness.letterRepo.markers.insert("letter-2026-06-29")
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.count == 1)
        #expect(harness.letterRepo.stored[0].classification == .quiet)
    }

    @Test("the adoption week's partial period never composes")
    func firstPeriodGate() async {
        let harness = Harness(profile: makeProfile(adoptedOn: "2026-07-01"))
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.isEmpty,
                "adopted mid-Jun-29-week: that period is partial")
    }

    @Test("lapsed: no letters; the archive stays what it was")
    func lapsedSkips() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        harness.membership.status = .lapsed
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.isEmpty)
    }

    @Test("active vacation defers composition; it is late, never wrong")
    func vacationDefers() async {
        let harness = Harness(profile: makeProfile(
            vacationMode: true, vacationStartedAt: Dates.days(-2), adoptedOn: "2026-05-01"
        ))
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.isEmpty)
    }

    @Test("a period fully inside a vacation composes nothing, ever")
    func fullVacationPeriodSkips() async {
        var profile = makeProfile(adoptedOn: "2026-05-01")
        profile.observationIntervals = [
            ObservationInterval(kind: .vacation, start: Dates.days(-15), end: Dates.days(-1)),
        ]
        let harness = Harness(profile: profile)
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.isEmpty)
    }

    @Test("the barrier flushes local writes BEFORE reading server state")
    func barrierOrder() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)

        let flush = harness.letterRepo.callLog.firstIndex(of: "flush")
        let serverRead = harness.letterRepo.callLog.firstIndex(of: "serverArchive")
        let create = harness.letterRepo.callLog.firstIndex { $0.hasPrefix("create:") }
        #expect(flush != nil && serverRead != nil && create != nil)
        #expect(flush! < serverRead!, "composition can never be blind to its own pending writes")
        #expect(serverRead! < create!)
    }

    @Test("an unreachable barrier means no letter yet - late beats wrong")
    func offlineBlocksComposition() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        harness.letterRepo.flushError = TestError()
        await harness.service.handleUserForeground(now: Dates.now)
        #expect(harness.letterRepo.stored.isEmpty)
    }

    @Test("losing the race: the winner is displayed, ours is discarded, no composed event")
    func firstWriterWins() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        // Another device already composed this period.
        let winner = Letter(
            id: "letter-2026-06-29",
            periodStart: Dates.days(-9), periodEndExclusive: Dates.days(-3),
            timeZoneId: TimeZone.current.identifier,
            classification: .steady, beatTypes: [.smallTruePositive],
            lineIds: ["small-positive:0"],
            fullRenderedText: "The other device's letter.\n\nFrom Mochi",
            privateRenderedText: "The other device's letter.\n\nFrom Mochi",
            petNameSnapshot: "Mochi", composedAt: Dates.days(-2),
            composerVersion: 1, copyDeckVersion: 1,
            periodSummaryHash: "cafe", readAt: nil
        )
        harness.letterRepo.stored = [winner]

        await harness.service.handleUserForeground(now: Dates.now)

        #expect(harness.letterRepo.stored == [winner], "one letter, theirs")
        #expect(!harness.telemetry.events.contains {
            if case .composed = $0 { return true } else { return false }
        }, "only the actual composer reports letter_composed")
        #expect(harness.service.unreadLetter == winner)
    }

    @Test("opening a letter sets readAt once and reports the source")
    func markOpened() async {
        let harness = Harness()
        harness.seedPreviousPeriodCompletions()
        await harness.service.handleUserForeground(now: Dates.now)
        let letter = harness.letterRepo.stored[0]

        await harness.service.markOpened(letter, source: .home, now: Dates.hours(1))

        #expect(harness.letterRepo.stored[0].readAt != nil)
        #expect(harness.service.unreadLetter == nil)
        #expect(harness.telemetry.events.contains {
            if case .opened(let source, _, _, let before) = $0 {
                return source == .home && before == false
            }
            return false
        })
    }

    // MARK: - Scheduling invariant + planner

    @Test("the planner hears about a letter only once the period is non-dormant")
    func plannedInputRequiresEngagement() async {
        let harness = Harness()
        #expect(await harness.service.plannedLetterInput(now: Dates.now) == nil,
                "no marker, no completions: never queue an invitation for someone who may vanish")

        harness.letterRepo.markers.insert("letter-2026-07-06")
        let input = await harness.service.plannedLetterInput(now: Dates.now)
        #expect(input?.periodStartDate == "2026-07-06")
        #expect(input.map { $0.fireAt > Dates.now } == true, "fires at the period cutoff")
    }

    @Test("no invitation while lapsed or on vacation")
    func plannedInputSuppressions() async {
        let harness = Harness()
        harness.letterRepo.markers.insert("letter-2026-07-06")
        harness.membership.status = .lapsed
        #expect(await harness.service.plannedLetterInput(now: Dates.now) == nil)
    }

    @Test("planner: the letter takes a slot, budget-last, and honors its toggle")
    func plannerIntegration() {
        let snapshot = MoodSnapshot(
            tasks: [], completionTimes: [], boosts: [],
            vacationMode: false, vacationResumeAt: nil, vacationStartedAt: nil,
            entitlementExpiry: nil, capturedAt: Dates.now
        )
        let letterInput = LetterNotificationInput(
            periodStartDate: "2026-07-06", fireAt: Dates.days(4)
        )
        var input = NotificationPlanInput(
            snapshot: snapshot, prefs: .standard, letter: letterInput,
            horizon: Dates.days(7)
        )

        let planned = NotificationPlanner.plan(input)
        #expect(planned.contains { $0.kind == .letter && $0.id == "letter-2026-07-06" })
        #expect(planned.first { $0.kind == .letter }?.fireAt == letterInput.fireAt)

        input.prefs.weeklyLetter = false
        #expect(!NotificationPlanner.plan(input).contains { $0.kind == .letter })

        input.prefs.weeklyLetter = true
        input.lapsed = true
        #expect(!NotificationPlanner.plan(input).contains { $0.kind == .letter })
    }

    @Test("under promise pressure the letter drops FIRST - it has a full in-app backstop")
    func plannerBudgetDrop() {
        // 64 future timed promises exhaust every slot (one stays reserved
        // for the backstop, which needs moodDips on to exist - keep the
        // default prefs where moodDips is off, so promises get 63).
        let tasks = (0..<70).map { index in
            makeTask(
                id: "t\(index)", title: "Task \(index)",
                dueAt: Dates.hours(Double(index) + 2), hasTime: true
            )
        }
        let snapshot = MoodSnapshot(
            tasks: tasks, completionTimes: [], boosts: [],
            vacationMode: false, vacationResumeAt: nil, vacationStartedAt: nil,
            entitlementExpiry: nil, capturedAt: Dates.now
        )
        let input = NotificationPlanInput(
            snapshot: snapshot, prefs: .standard,
            letter: LetterNotificationInput(periodStartDate: "2026-07-06", fireAt: Dates.days(4)),
            horizon: Dates.days(7)
        )
        let planned = NotificationPlanner.plan(input)
        #expect(!planned.contains { $0.kind == .letter },
                "the letter is the first thing dropped under slot pressure")
        #expect(planned.count <= NotificationPlanner.Constants.slotCap)
    }

    @Test("vacation silences the letter invitation entirely")
    func plannerVacationSuppression() {
        let snapshot = MoodSnapshot(
            tasks: [], completionTimes: [], boosts: [],
            vacationMode: true, vacationResumeAt: Dates.days(6), vacationStartedAt: Dates.days(-1),
            entitlementExpiry: nil, capturedAt: Dates.now
        )
        let input = NotificationPlanInput(
            snapshot: snapshot, prefs: .standard,
            letter: LetterNotificationInput(periodStartDate: "2026-07-06", fireAt: Dates.days(4)),
            horizon: Dates.days(7)
        )
        #expect(!NotificationPlanner.plan(input).contains { $0.kind == .letter })
    }

    @Test("the differ owns letter ids - a stale invitation gets cancelled")
    func differOwnsLetterIds() {
        #expect(NotificationPlanDiffer.isOurs("letter-2026-07-06"))
        let diff = NotificationPlanDiffer.diff(desired: [], pendingIds: ["letter-2026-06-29"])
        #expect(diff.removeIds == ["letter-2026-06-29"])
    }

    @Test("letter telemetry buckets are coarse and honest")
    func telemetryBuckets() {
        #expect(LetterTelemetryBuckets.words(55) == "40-69")
        #expect(LetterTelemetryBuckets.words(121) == "over-120")
        #expect(LetterTelemetryBuckets.timeToOpen(
            composedAt: Dates.now, openedAt: Dates.hours(3)
        ) == "1-12h")
    }
}
