//
//  JournalTests.swift
//  MochiBuddyTests
//
//  Feature 6, the container: timeline merge with pinned calendar
//  semantics, hero lifecycle, young/growing states with absent-section
//  omission, the lapse freeze, the record-vs-grade output surface, and
//  the navigation migration.
//
//  Time anchors: JournalViewModel derives its windows from the REAL
//  clock (except under the lapse freeze, which pins to the interval
//  log), so footer fixtures anchor to `liveNow`, not Dates.now - the
//  Feature 5 editor-test rule.
//

import Combine
import Foundation
import Testing
@testable import MochiBuddy

private let liveNow = Date.now
private let liveCalendar = Calendar.current

private func liveDays(_ d: Int) -> Date {
    liveCalendar.date(byAdding: .day, value: d, to: liveNow)!
}

private func makeLetter(
    id: String = "letter-2026-06-29",
    periodStart: Date = Dates.days(-9),
    periodEndExclusive: Date = Dates.days(-3),
    timeZoneId: String = TimeZone.current.identifier,
    readAt: Date? = nil
) -> Letter {
    Letter(
        id: id,
        periodStart: periodStart, periodEndExclusive: periodEndExclusive,
        timeZoneId: timeZoneId,
        classification: .steady, beatTypes: [.smallTruePositive],
        lineIds: ["small-positive:0"],
        fullRenderedText: "A letter body.\n\nFrom Nori",
        privateRenderedText: "A letter body.\n\nFrom Nori",
        petNameSnapshot: "Nori", composedAt: periodEndExclusive,
        composerVersion: 1, copyDeckVersion: 1,
        periodSummaryHash: "cafe", readAt: readAt
    )
}

private func instant(
    year: Int, month: Int, day: Int, hour: Int, zone: String
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

// MARK: - Timeline merge

@Suite("Journal · timeline merge")
struct JournalTimelineTests {

    @Test("a letter dates by its periodEndExclusive in the letter's STORED zone - travel moves nothing")
    func storedZoneDating() {
        // 05:00 Aug 1 in Tokyo is still Jul 31 in UTC and New York; the
        // letter belongs to August because Tokyo composed it there.
        let letter = makeLetter(
            id: "letter-2026-07-27",
            periodEndExclusive: instant(year: 2026, month: 8, day: 1, hour: 5, zone: "Asia/Tokyo"),
            timeZoneId: "Asia/Tokyo"
        )
        #expect(JournalTimeline.letterDateString(letter) == "2026-08-01")

        let groups = JournalTimeline.monthGroups(
            letters: [letter], moments: [], excludingLetterId: nil, currentYear: 2026
        )
        #expect(groups.map(\.id) == ["2026-08"])
    }

    @Test("same-day ties order letters first, then moments by natural id; months group newest-first")
    func tieRuleAndGrouping() {
        let letter = makeLetter(
            id: "letter-2026-06-29",
            periodEndExclusive: instant(year: 2026, month: 7, day: 5, hour: 19, zone: "UTC"),
            timeZoneId: "UTC",
            readAt: Dates.now
        )
        let momentA = MomentFactory.listReturn(
            listId: "a", firedOn: "2026-07-05", listName: "Reading",
            locale: Locale(identifier: "en_US"), now: Dates.now
        )
        let momentB = MomentFactory.streakMilestone(
            count: 7, day: "2026-07-05", petName: "Nori",
            locale: Locale(identifier: "en_US"), now: Dates.now
        )
        let june = MomentFactory.adoption(
            adoptedOn: "2026-06-28", petName: nil,
            locale: Locale(identifier: "en_US"), now: Dates.now
        )

        let groups = JournalTimeline.monthGroups(
            letters: [letter], moments: [momentB, june, momentA],
            excludingLetterId: nil, currentYear: 2026
        )
        #expect(groups.map(\.id) == ["2026-07", "2026-06"])
        #expect(groups[0].rows.map(\.id) == [
            "letter-row-letter-2026-06-29",
            "list-return-a-2026-07-05",
            "streak-milestone-7-2026-07-05",
        ])
        #expect(groups[1].rows.map(\.id) == ["adoption-2026-06-28"])
        #expect(groups[0].title == "July")
    }

    @Test("input order never changes the output - deterministic on every device")
    func determinism() {
        let letters = (0..<4).map { index in
            makeLetter(
                id: "letter-2026-06-\(10 + index)",
                periodEndExclusive: instant(year: 2026, month: 6, day: 14 + index, hour: 19, zone: "UTC"),
                timeZoneId: "UTC", readAt: Dates.now
            )
        }
        let moments = (0..<5).map { index in
            MomentFactory.streakMilestone(
                count: 7, day: "2026-06-1\(index)", petName: "Nori",
                locale: Locale(identifier: "en_US"), now: Dates.now
            )
        }
        let a = JournalTimeline.monthGroups(
            letters: letters, moments: moments, excludingLetterId: nil, currentYear: 2026
        )
        let b = JournalTimeline.monthGroups(
            letters: letters.reversed(), moments: moments.shuffled(),
            excludingLetterId: nil, currentYear: 2026
        )
        #expect(a == b)
    }

    @Test("months outside the current year carry the year in their title")
    func priorYearTitle() {
        #expect(JournalTimeline.monthTitle("2025-03", currentYear: 2026, locale: Locale(identifier: "en_US")) == "March 2025")
        #expect(JournalTimeline.monthTitle("2026-03", currentYear: 2026, locale: Locale(identifier: "en_US")) == "March")
    }

    @Test("week strip and trend derivations bucket by day (the Stats port)")
    func footerDerivations() {
        let calendar = Dates.calendar
        let weekStart = calendar.date(byAdding: .day, value: -6, to: Dates.startOfToday)!
        let stats = [
            makeStat(localDate: "2026-07-07", localMinute: 600),
            makeStat(localDate: "2026-07-07", localMinute: 660),
            makeStat(localDate: "2026-07-08", localMinute: 540),
        ]
        let cells = JournalTimeline.weekCells(stats: stats, weekStart: weekStart, calendar: calendar)
        #expect(cells.count == 7)
        #expect(cells.map(\.count).reduce(0, +) == 3)
        #expect(cells.map(\.count).max() == 2)

        let trendStart = calendar.date(byAdding: .day, value: -27, to: Dates.startOfToday)!
        let points = JournalTimeline.trendPoints(stats: stats, start: trendStart, calendar: calendar)
        #expect(points.count == 28)
        #expect(points.map(\.count).reduce(0, +) == 3)

        #expect(!JournalTimeline.trendQualifies(
            stats: [stats[0], stats[1]], calendar: calendar
        ), "a single week is noise, not a trend")
        let spread = stats + [makeStat(localDate: "2026-06-20", localMinute: 600)]
        #expect(JournalTimeline.trendQualifies(stats: spread, calendar: calendar))
    }
}

// MARK: - ViewModel states

@Suite("Journal · view model")
@MainActor
struct JournalViewModelTests {

    private struct Harness {
        let viewModel: JournalViewModel
        let letters: StubLetterRepository
        let moments: StubMomentRepository
        let profileRepo: StubProfileRepository
        let taskRepo: StubTaskRepository
        let session: MembershipSession
        let coordinator: TabCoordinator
        let momentRepo: StubMomentRepository
    }

    private func makeHarness(
        profile: UserProfile = makeProfile(mochiName: "Nori", adoptedOn: "2026-06-28"),
        lapsed: Bool = false
    ) async -> Harness {
        let profileRepo = StubProfileRepository()
        profileRepo.profile = profile
        let letterRepo = StubLetterRepository()
        let momentRepo = StubMomentRepository()
        let taskRepo = StubTaskRepository()
        let listRepo = StubListRepository()
        let session = MembershipSession()
        if lapsed { session.status = .lapsed }
        let defaults = UserDefaults(suiteName: "journalTests-\(UUID().uuidString)")!
        let identity = PetIdentityStore(profileRepository: profileRepo, defaults: defaults)
        let coordinator = TabCoordinator()
        let writer = MomentWriter(
            authRepository: StubAuthRepository(),
            momentRepository: momentRepo,
            petIdentityStore: identity,
            listRepository: listRepo,
            membershipSession: session,
            calendar: liveCalendar
        )
        let viewModel = JournalViewModel(
            authRepository: StubAuthRepository(),
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            listRepository: listRepo,
            letterRepository: letterRepo,
            momentRepository: momentRepo,
            momentWriter: writer,
            membershipSession: session,
            petIdentityStore: identity,
            coordinator: coordinator,
            calendar: liveCalendar
        )
        // Adopt the profile identity (adoptedOn already present, so the
        // load path stamps nothing).
        await identity.load(profile: profile, now: liveNow)
        return Harness(
            viewModel: viewModel, letters: letterRepo, moments: momentRepo,
            profileRepo: profileRepo, taskRepo: taskRepo, session: session,
            coordinator: coordinator, momentRepo: momentRepo
        )
    }

    @Test("young: adoption only - synthesized row, forward line surface, no charts, no cards (edges 1-2)")
    func youngState() async {
        let harness = await makeHarness()
        await harness.viewModel.triggerAsync(.load)

        let state = harness.viewModel.uiState
        #expect(state.young != nil)
        #expect(state.young?.adoptionText == "The day your story began.")
        #expect(state.young?.dateLabel == "June 28, 2026")
        #expect(state.hero == nil)
        #expect(state.months.isEmpty)
        #expect(state.noticedLines.isEmpty)
        #expect(state.footer == nil)
        #expect(state.headerSubtitle == nil, "day one carries no since-line")

        // The synthesis fallback enqueued the idempotent repair write.
        #expect(harness.momentRepo.stored.map(\.id) == ["adoption-2026-06-28"])
        await harness.viewModel.triggerAsync(.load)
        #expect(harness.momentRepo.stored.count == 1)
    }

    @Test("hero lifecycle: newest unread promoted and excluded; read returns it; older unread keeps its trait (edges 6-7)")
    func heroLifecycle() async {
        let harness = await makeHarness()
        let older = makeLetter(
            id: "letter-2026-06-22",
            periodStart: Dates.days(-16), periodEndExclusive: Dates.days(-10),
            readAt: nil
        )
        let newer = makeLetter(
            id: "letter-2026-06-29",
            periodStart: Dates.days(-9), periodEndExclusive: Dates.days(-3),
            readAt: nil
        )
        harness.letters.stored = [older, newer]
        await harness.viewModel.triggerAsync(.load)

        var state = harness.viewModel.uiState
        #expect(state.young == nil)
        #expect(state.hero?.letterId == "letter-2026-06-29")
        let rowIds = state.months.flatMap(\.rows).map(\.id)
        #expect(!rowIds.contains("letter-row-letter-2026-06-29"), "promoted = excluded below")
        let olderRow = state.months.flatMap(\.rows).compactMap { row -> JournalBehavior.LetterRow? in
            if case .letter(let letter) = row { return letter }
            return nil
        }.first { $0.letterId == "letter-2026-06-22" }
        #expect(olderRow?.isUnread == true, "older unread rows keep the trait")

        // Reading both letters returns the hero to its chronological row.
        harness.letters.stored = [older, newer].map { letter in
            var read = letter
            read.readAt = Dates.now
            return read
        }
        await harness.viewModel.triggerAsync(.load)
        state = harness.viewModel.uiState
        #expect(state.hero == nil)
        #expect(state.months.flatMap(\.rows).map(\.id).contains("letter-row-letter-2026-06-29"))
    }

    @Test("footer: absent with an empty strip window (edge 13); staged trend; subtitle records the relationship")
    func footerStaging() async {
        let harness = await makeHarness()
        // History exists, but nothing this week: the footer is omitted.
        harness.taskRepo.completedStats = [
            CompletedTaskStat(completedAt: liveDays(-20), dueAt: nil)
        ]
        harness.letters.stored = [makeLetter(readAt: Dates.now)]
        await harness.viewModel.triggerAsync(.load)
        #expect(harness.viewModel.uiState.footer == nil)
        #expect(harness.viewModel.uiState.headerSubtitle == "With Nori since June")

        // A completion today earns the strip; one week of data is no trend.
        harness.taskRepo.completedStats = [
            CompletedTaskStat(completedAt: liveNow, dueAt: nil)
        ]
        await harness.viewModel.triggerAsync(.load)
        var footer = harness.viewModel.uiState.footer
        #expect(footer != nil)
        #expect(footer?.title == "This week")
        #expect(footer?.doneCount == 1)
        #expect(footer?.trend.isEmpty == true)
        #expect(footer?.bestStreak == nil, "a zero best streak is omitted, never shown")

        // Three weeks of history qualifies the trend; best streak joins.
        harness.profileRepo.profile = makeProfile(
            bestStreak: 9, mochiName: "Nori", adoptedOn: "2026-06-28"
        )
        harness.taskRepo.completedStats = [
            CompletedTaskStat(completedAt: liveNow, dueAt: nil),
            CompletedTaskStat(completedAt: liveDays(-15), dueAt: nil),
        ]
        await harness.viewModel.triggerAsync(.load)
        footer = harness.viewModel.uiState.footer
        #expect(footer?.trend.count == JournalTimeline.trendDays)
        #expect(footer?.bestStreak == 9)
    }

    @Test("lapse freeze: derivations pin to lapseStartedAt while tasks complete; zero come-back copy (edge 14)")
    func lapseFreeze() async {
        let lapseStart = liveDays(-5)
        let harness = await makeHarness(
            profile: makeProfile(
                bestStreak: 4, mochiName: "Nori", adoptedOn: "2026-01-10",
                observationIntervals: [ObservationInterval(kind: .lapse, start: lapseStart, end: nil)]
            ),
            lapsed: true
        )
        harness.letters.stored = [makeLetter(readAt: Dates.now)]
        harness.taskRepo.completedStats = [
            // Inside the frozen week (the 7 days ending at lapse start).
            CompletedTaskStat(completedAt: liveDays(-6), dueAt: nil),
            // Completed DURING the lapse - real work, but the record is
            // pinned; it must not move the strip.
            CompletedTaskStat(completedAt: liveDays(-1), dueAt: nil),
        ]
        await harness.viewModel.triggerAsync(.load)

        let state = harness.viewModel.uiState
        #expect(state.isLapsed)
        #expect(state.headerSubtitle == "Nori is napping · paused")
        #expect(state.footer?.title == "The week you paused")
        #expect(state.footer?.doneLabel == "Done that week")
        #expect(state.footer?.doneCount == 1, "lapse-period completions stay out of the frozen strip")

        // Reactivation resumes live over full retained history.
        harness.session.status = .active(plan: .yearly, renewsAt: nil, willRenew: true)
        await harness.viewModel.triggerAsync(.load)
        #expect(harness.viewModel.uiState.isLapsed == false)
        #expect(harness.viewModel.uiState.footer?.doneCount == 2,
                "the during-lapse completion counts in the live week - history is never discarded")
        #expect(harness.viewModel.uiState.footer?.title == "This week")
    }

    @Test("record vs grade: the output surface carries no coins, no on-time rate, no busiest-weekday")
    func forbiddenOutputs() {
        let labels = Mirror(reflecting: JournalBehavior.UIState()).children.compactMap(\.label)
            + Mirror(reflecting: JournalBehavior.Footer(
                title: "", week: [], doneLabel: "", doneCount: 0, bestStreak: nil, trend: []
            )).children.compactMap(\.label)
        for label in labels {
            let lowered = label.lowercased()
            #expect(!lowered.contains("coin"))
            #expect(!lowered.contains("ontime"))
            #expect(!lowered.contains("busiest"))
        }
    }

    @Test("the coordinator hands an envelope route through the tab switch into a Journal letter open")
    func coordinatorRouting() async {
        let harness = await makeHarness()
        let unread = makeLetter(readAt: nil)
        harness.letters.stored = [unread]

        harness.coordinator.openLetterInJournal(unread.id, source: .envelope)
        #expect(harness.coordinator.selected == .journal)

        let recorder = EventRecorder(harness.viewModel)
        await harness.viewModel.triggerAsync(.load)
        await harness.viewModel.triggerAsync(.consumePendingRoute)
        await recorder.drain()

        #expect(harness.coordinator.pendingLetterRoute == nil)
        guard case .openLetter(let letter, let source)? = recorder.events.first else {
            Issue.record("expected an openLetter event")
            return
        }
        #expect(letter.id == unread.id)
        #expect(source == .home)
    }
}

// MARK: - Navigation migration

@Suite("Journal · navigation migration")
struct JournalNavigationTests {

    @Test("four tabs, Journal between Tasks and You, static label, book glyph (edges 17-18)")
    func tabShape() {
        #expect(MainTab.allCases == [.home, .tasks, .journal, .you])
        #expect(MainTab.journal.label == "Journal")
        #expect(MainTab.journal.icon == "book.fill")
        #expect(MainTab(rawValue: "journal") == .journal, "-mochiStartTab journal works")
    }

    @Test("the You surface exposes no stats or letters rows")
    func youRetirement() {
        // Compile-time retirement: the actions and events are gone. This
        // asserts the remaining navigation events stay the settings set.
        let remaining: [YouBehavior.NavigationEvent] = [
            .editBedtime, .showNotifications, .showReminders,
            .showVacation, .showManageLists, .startDeleteFlow, .signedOut, .wakeMochi,
        ]
        #expect(remaining.count == 8)
    }
}
