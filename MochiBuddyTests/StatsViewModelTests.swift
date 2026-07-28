//
//  StatsViewModelTests.swift
//  MochiBuddyTests
//
//  The chart derivations: 4-week trend fill, on-time math, the Best Hours
//  cards, tiles, memory rows, and the per-list breakdown. Fixture dates
//  anchor to the REAL clock (the VM reads Date.now), same doctrine as
//  JournalTests.
//

import Foundation
import Testing
@testable import MochiBuddy

private let calendar = Calendar.current
private var startOfToday: Date { calendar.startOfDay(for: .now) }
private func daysAgo(_ d: Int) -> Date { calendar.date(byAdding: .day, value: -d, to: startOfToday)! }

/// A stat whose instant is real-now-relative and whose local context
/// names the same moment in the device zone - both bucketing rules agree.
private func liveStat(
    daysAgo d: Int,
    minuteOfDay: Int = 600,
    dueAt: Date? = nil,
    listId: String? = nil,
    isRecurring: Bool = false,
    estimatedMinutes: Int? = nil
) -> CompletedTaskStat {
    let instant = daysAgo(d).addingTimeInterval(TimeInterval(minuteOfDay * 60))
    return CompletedTaskStat(
        taskId: UUID().uuidString,
        seriesId: nil,
        completedAt: instant,
        dueAt: dueAt,
        listId: listId,
        hasTime: false,
        isRecurring: isRecurring,
        source: .mochi,
        rescheduleCount: 0,
        estimatedMinutes: estimatedMinutes,
        localContext: CompletionLocalContext(
            localDate: CivilDay(of: instant, in: calendar).dateString,
            localMinute: minuteOfDay,
            timeZoneId: TimeZone.current.identifier
        )
    )
}

@MainActor
private func makeStatsVM(
    stats: [CompletedTaskStat] = [],
    lists: [TaskList] = [],
    profile: UserProfile = makeProfile(coins: 40, streak: 3, bestStreak: 9)
) -> StatsViewModel {
    let taskRepo = StubTaskRepository()
    taskRepo.completedStats = stats
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    return StatsViewModel(
        authRepository: StubAuthRepository(),
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        listRepository: listRepo,
        petIdentityStore: PetIdentityStore(
            profileRepository: profileRepo,
            defaults: UserDefaults(suiteName: "statsTests-\(UUID().uuidString)")!
        )
    )
}

@Suite("Stats · trend")
@MainActor
struct StatsTrendTests {

    @Test("the trend is 28 zero-filled daily points with counts on seeded days")
    func trendFill() async {
        let stats = [
            liveStat(daysAgo: 0, minuteOfDay: 60),
            liveStat(daysAgo: 0, minuteOfDay: 120),
            liveStat(daysAgo: 3, minuteOfDay: 60),
        ]
        let vm = makeStatsVM(stats: stats)
        await vm.triggerAsync(.load)

        let trend = vm.uiState.trend
        #expect(trend.count == StatsBehavior.TimeRange.month.days, "month is the default range")
        #expect(trend.last?.count == 2, "today is the last point")
        #expect(trend[trend.count - 4].count == 1, "three days ago")
        #expect(trend.map(\.count).reduce(0, +) == 3, "every other day is zero")
    }

    @Test("tiles follow the selected range; the streak strip always slices 7 days")
    func rangeScopesTiles() async {
        let stats = [
            liveStat(daysAgo: 1),
            liveStat(daysAgo: 10),
            liveStat(daysAgo: 20),
        ]
        let vm = makeStatsVM(stats: stats)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.tiles.first { $0.id == "done" }?.value == "3", "month default counts 28 days")
        #expect(vm.uiState.week.map(\.count).reduce(0, +) == 1, "the heat strip stays weekly")

        await vm.triggerAsync(.rangeChanged(.week))
        #expect(vm.uiState.tiles.first { $0.id == "done" }?.value == "1")
        #expect(vm.uiState.tiles.first { $0.id == "done" }?.title == "Done this week")
    }

    @Test("3 months buckets the trend into 13 weekly points")
    func threeMonthsWeeklyBuckets() async {
        let stats = [
            liveStat(daysAgo: 0),
            liveStat(daysAgo: 1),
            liveStat(daysAgo: 40),
        ]
        let vm = makeStatsVM(stats: stats)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.rangeChanged(.threeMonths))

        let trend = vm.uiState.trend
        #expect(vm.uiState.trendUnit == .week)
        #expect(trend.count == 13)
        #expect(trend.map(\.count).reduce(0, +) == 3, "weekly buckets keep every completion")
    }

    @Test("on-time math: undated counts on-time, late counts against")
    func onTimeMath() {
        let due = startOfToday
        let stats = [
            liveStat(daysAgo: 1, dueAt: due),          // on time (yesterday, due today)
            liveStat(daysAgo: 0, minuteOfDay: 600, dueAt: due),  // late (10:00 vs midnight due)
            liveStat(daysAgo: 0),                      // undated → on time
            liveStat(daysAgo: 0),                      // undated → on time
        ]
        #expect(StatsViewModel.onTimeText(stats) == "75%")
        #expect(StatsViewModel.onTimeText([]) == "–")
    }

    @Test("the trend caption carries no busiest-weekday clause (D9)")
    func trendCaptionOnTimeOnly() async {
        let vm = makeStatsVM(stats: [liveStat(daysAgo: 0)])
        await vm.triggerAsync(.load)
        #expect(vm.uiState.trendCaption == "100% on time")
    }
}

@Suite("Stats · best hours histogram")
struct BestHoursHistogramTests {

    private func entry(minute: Int, day: String = "2026-07-08") -> BestHours.Entry {
        BestHours.Entry(localMinute: minute, day: CivilDay(day)!)
    }

    @Test("the axis runs 5a to 5a: a 2am completion lands at the far right, not clipped")
    func axisOrigin() {
        #expect(BestHours.axisMinute(300) == 0, "5:00 is the origin")
        #expect(BestHours.axisMinute(2 * 60) == 21 * 60, "2am reads as late")
        #expect(BestHours.axisMinute(0) == 19 * 60)
    }

    @Test("recurring completions are excluded from the derivation (D2)")
    func recurringExcluded() {
        let stats = [
            liveStat(daysAgo: 1, minuteOfDay: 480),
            liveStat(daysAgo: 2, minuteOfDay: 480, isRecurring: true),
        ]
        #expect(BestHours.entries(stats: stats).count == 1)
    }

    @Test("the best 3-hour window is highlighted and in-window share is its share of all bars")
    func peakWindow() {
        // 6 completions 10a-1p (buckets 5,6,7), 2 elsewhere.
        let entries = [
            entry(minute: 10 * 60), entry(minute: 10 * 60 + 30), entry(minute: 11 * 60),
            entry(minute: 11 * 60 + 30), entry(minute: 12 * 60), entry(minute: 12 * 60 + 30),
            entry(minute: 20 * 60), entry(minute: 21 * 60),
        ]
        let histogram = BestHours.histogram(entries: entries)
        #expect(histogram.peakStart == 5, "10a is 5 buckets past 5a")
        #expect(BestHours.peakRangeLabel(start: 5) == "10a to 1p")
        #expect(abs(histogram.inWindowShare - 0.75) < 0.001)
        #expect(histogram.secondaryStart == nil, "two evening completions are under the C4 floor")
    }

    @Test("an empty range yields no histogram peak and no card")
    func emptyHistogram() {
        let histogram = BestHours.histogram(entries: [])
        #expect(histogram.peakStart == nil)
        #expect(StatsViewModel.bestHoursCard(
            histogram: histogram, rows: [], petName: "Mochi", calendar: calendar
        ) == nil)
    }

    @Test("a second wind qualifies only past its own floor AND half the peak's share (C4)")
    func secondWindFloor() {
        // Peak: 6 completions around 9a across 6 dates. Secondary at 8p:
        // 5 completions across 5 dates - at least half the peak share.
        var entries: [BestHours.Entry] = []
        for day in 1...6 {
            entries.append(entry(minute: 9 * 60, day: "2026-07-0\(day)"))
        }
        for day in 1...5 {
            entries.append(entry(minute: 20 * 60, day: "2026-07-1\(day)"))
        }
        let histogram = BestHours.histogram(entries: entries)
        #expect(histogram.secondaryStart != nil)
        #expect(BestHours.bandPhrase(windowStart: histogram.secondaryStart ?? 0) == "evening")

        // A 4-completion evening bump stays under the count floor - noise,
        // not a second wind, exactly the comp's sub-3% case.
        var thin = entries.filter { $0.localMinute == 9 * 60 }
        thin.append(entry(minute: 20 * 60, day: "2026-07-11"))
        thin.append(entry(minute: 20 * 60, day: "2026-07-12"))
        thin.append(entry(minute: 20 * 60, day: "2026-07-13"))
        thin.append(entry(minute: 20 * 60, day: "2026-07-14"))
        #expect(BestHours.histogram(entries: thin).secondaryStart == nil)
    }
}

@Suite("Stats · day by day rows")
struct BestHoursWeekdayRowTests {

    /// Entries all on one weekday: `weeksAgo` steps of 7 days from a fixed
    /// Wednesday, so every fixture lands on the same row deterministically.
    private func wednesday(weeksAgo: Int, minute: Int) -> BestHours.Entry {
        BestHours.Entry(localMinute: minute, day: CivilDay("2026-07-08")!.advanced(by: -7 * weeksAgo))
    }

    @Test("a row earns its capsule at 5 completions across 3 dates (D5); thin rows keep the dot only")
    func rowQualification() {
        let entries = [
            wednesday(weeksAgo: 0, minute: 600), wednesday(weeksAgo: 0, minute: 620),
            wednesday(weeksAgo: 1, minute: 640), wednesday(weeksAgo: 1, minute: 660),
            wednesday(weeksAgo: 2, minute: 680),
        ]
        let rows = BestHours.weekdayRows(entries: entries, calendar: calendar)
        let wed = rows.first { $0.weekday == 4 }!
        #expect(wed.qualifies)
        #expect(wed.q1 != nil && wed.q3 != nil)
        #expect(wed.typical != nil)

        // Four completions on two dates: below both floors - dot only.
        let thinRows = BestHours.weekdayRows(entries: Array(entries.prefix(4)), calendar: calendar)
        let thinWed = thinRows.first { $0.weekday == 4 }!
        #expect(!thinWed.qualifies)
        #expect(thinWed.q1 == nil && thinWed.q3 == nil)
        #expect(thinWed.typical != nil, "we know roughly when, not how consistently")
    }

    @Test("one heroic day cannot reshape a row - contributions cap at 3 per date")
    func dayCap() {
        let heroic = (0..<10).map { wednesday(weeksAgo: 0, minute: 600 + $0) }
        let rows = BestHours.weekdayRows(entries: heroic, calendar: calendar)
        #expect(rows.first { $0.weekday == 4 }!.count == 3)
    }

    @Test("a 2am completion belongs to the previous day's row, matching the 5a axis")
    func nightWrapsToPreviousRow() {
        let entries = [BestHours.Entry(localMinute: 2 * 60, day: CivilDay("2026-07-09")!)]
        let rows = BestHours.weekdayRows(entries: entries, calendar: calendar)
        #expect(rows.first { $0.weekday == 4 }!.count == 1, "Thursday 2am reads as late Wednesday")
        #expect(rows.first { $0.weekday == 5 }!.count == 0)
    }

    @Test("the typical dot is a circular center, and its label renders compactly")
    func typicalLabel() {
        // 11:30p Wednesday and 12:30a Thursday-the-civil-day - both are
        // late-Wednesday nights on the 5a axis, one row.
        let entries = [
            BestHours.Entry(localMinute: 23 * 60 + 30, day: CivilDay("2026-07-08")!),
            BestHours.Entry(localMinute: 30, day: CivilDay("2026-07-02")!),
        ]
        let rows = BestHours.weekdayRows(entries: entries, calendar: calendar)
        let typical = rows.first { $0.weekday == 4 }!.typical
        #expect(typical == BestHours.axisMinute(0), "23:30 and 00:30 cluster to midnight, never noon")
        #expect(BestHours.timeLabel(axisMinute: typical!) == "12:00a")
        #expect(BestHours.timeLabel(axisMinute: BestHours.axisMinute(650)) == "10:50a")
    }

    @Test("Day by day stays empty on the Week range even when rows qualify (D6)")
    func weekRangeHidesRows() {
        let entries = (0..<5).map { wednesday(weeksAgo: $0 % 3, minute: 600 + $0) }
        let rows = BestHours.weekdayRows(entries: entries, calendar: calendar)
        #expect(rows.contains { $0.qualifies })
        #expect(StatsViewModel.dayByDayRows(rows, range: .week, calendar: calendar).isEmpty)
        #expect(!StatsViewModel.dayByDayRows(rows, range: .month, calendar: calendar).isEmpty)
    }
}

@Suite("Stats · best hours caption")
struct BestHoursCaptionTests {

    private func qualifiedRow(weekday: Int) -> BestHours.WeekdayRow {
        BestHours.WeekdayRow(
            weekday: weekday, count: 6, dateCount: 4, qualifies: true,
            first: 300, last: 500, q1: 350, q3: 450, typical: 400
        )
    }

    private func thinRow(weekday: Int) -> BestHours.WeekdayRow {
        BestHours.WeekdayRow(
            weekday: weekday, count: 1, dateCount: 1, qualifies: false,
            first: 400, last: 400, q1: nil, q3: nil, typical: 400
        )
    }

    private let morningPeak = BestHours.Histogram(
        buckets: [Int](repeating: 1, count: 24), peakStart: 4, inWindowShare: 0.5, secondaryStart: nil
    )

    @Test("second wind outranks every other state and names both bands")
    func secondWind() {
        let histogram = BestHours.Histogram(
            buckets: [Int](repeating: 1, count: 24), peakStart: 4, inWindowShare: 0.5, secondaryStart: 14
        )
        let line = BestHours.caption(
            histogram: histogram, rows: (1...7).map(qualifiedRow), petName: "Mochi", calendar: calendar
        )
        #expect(line == "You get the most done in the morning, with a smaller second wind in the evening. Mochi sees it.")
    }

    @Test("Day by day's caption names thin days naturally, with Sat+Sun folding into the weekend")
    func thinDays() {
        let rows = [qualifiedRow(weekday: 2), qualifiedRow(weekday: 3), qualifiedRow(weekday: 4),
                    thinRow(weekday: 5), qualifiedRow(weekday: 6), thinRow(weekday: 7), thinRow(weekday: 1)]
        let line = BestHours.dayByDayCaption(histogram: morningPeak, rows: rows, petName: "Mochi", calendar: calendar)
        #expect(line.hasPrefix("Mochi has a good read on your week."))
        #expect(line.contains("Thursday"))
        #expect(line.contains("the weekend"))
        #expect(!line.contains("Saturday") && !line.contains("Sunday"))
        #expect(line.hasSuffix("are still quiet."))
    }

    @Test("a single thin day reads grammatically")
    func singleThinDay() {
        let rows = (1...6).map(qualifiedRow) + [thinRow(weekday: 7)]
        let line = BestHours.dayByDayCaption(histogram: morningPeak, rows: rows, petName: "Mochi", calendar: calendar)
        #expect(line.hasSuffix("Saturday is still quiet."))
    }

    @Test("card 1 names the peak once rows qualify; no qualified rows means still learning")
    func fullReadAndLearning() {
        let full = BestHours.caption(
            histogram: morningPeak, rows: (1...7).map(qualifiedRow), petName: "Mochi", calendar: calendar
        )
        #expect(full == "You get the most done in the morning. Mochi sees the pattern.")

        let learning = BestHours.caption(
            histogram: morningPeak, rows: (1...7).map(thinRow), petName: "Mochi", calendar: calendar
        )
        #expect(learning == "Still learning your week. Here's your day so far.")

        // Card 2's full read mirrors the pattern line - the comp's 1b state.
        let fullRead = BestHours.dayByDayCaption(
            histogram: morningPeak, rows: (1...7).map(qualifiedRow), petName: "Mochi", calendar: calendar
        )
        #expect(fullRead == "You get the most done in the morning. Mochi sees the pattern.")
    }
}

@Suite("Stats · tiles")
struct StatsTilesTests {

    @Test("with an adoption date the fourth tile counts days together, adoption day inclusive")
    func daysTogether() {
        let today = CivilDay("2026-07-25")!
        let tiles = StatsViewModel.tiles(
            rangeDone: 4, rangeOnTime: "80%", range: .week, bestStreak: 9, coins: 40,
            adoptedOn: "2026-07-08", today: today
        )
        let together = tiles.first { $0.id == "together" }
        #expect(together?.value == "18")
        #expect(together?.subtitle.contains("Jul") == true)
        #expect(tiles.contains { $0.id == "coins" } == false)
    }

    @Test("without an adoption date the coins tile fills the grid")
    func coinsFallback() {
        let tiles = StatsViewModel.tiles(
            rangeDone: 0, rangeOnTime: "–", range: .week, bestStreak: 1, coins: 40,
            adoptedOn: nil, today: CivilDay("2026-07-25")!
        )
        #expect(tiles.contains { $0.id == "coins" && $0.value == "40" })
        let best = tiles.first { $0.id == "best" }
        #expect(best?.subtitle == "day", "singular at 1")
    }

    @Test("the effort tile shows a rough half-hour total with honest coverage")
    func effortTile() {
        let stats = [
            liveStat(daysAgo: 0, estimatedMinutes: 60),
            liveStat(daysAgo: 1, estimatedMinutes: 60),
            liveStat(daysAgo: 2, estimatedMinutes: 30),
            liveStat(daysAgo: 3),
            liveStat(daysAgo: 4, isRecurring: true, estimatedMinutes: 15),
        ]
        let tile = StatsViewModel.effortTile(stats: stats)
        // 60+60+30+15 = 165, rounded to 180 - recurring time counts (D12).
        #expect(tile.value == "~3h")
        #expect(tile.subtitle == "4 of 5 rated")

        let small = StatsViewModel.effortTile(stats: [liveStat(daysAgo: 0, estimatedMinutes: 15)])
        #expect(small.value == "~30m", "the floor keeps a lone Tiny visible, never ~0")

        let mixed = StatsViewModel.effortTile(stats: [
            liveStat(daysAgo: 0, estimatedMinutes: 120),
            liveStat(daysAgo: 1, estimatedMinutes: 30),
        ])
        #expect(mixed.value == "~2h 30m")
    }

    @Test("with nothing rated the effort tile shows a dash, matching onTimeText")
    func effortTileUnrated() {
        let tile = StatsViewModel.effortTile(stats: [liveStat(daysAgo: 0)])
        #expect(tile.value == "–")
        #expect(tile.subtitle == "nothing rated yet")
    }

    @Test("tile copy names the selected window")
    func rangeCopy() {
        let month = StatsViewModel.tiles(
            rangeDone: 9, rangeOnTime: "90%", range: .month, bestStreak: 2, coins: 0,
            adoptedOn: nil, today: CivilDay("2026-07-25")!
        )
        #expect(month.first { $0.id == "done" }?.title == "Done this month")
        #expect(month.first { $0.id == "completion" }?.subtitle == "this month")
        let quarter = StatsViewModel.tiles(
            rangeDone: 9, rangeOnTime: "90%", range: .threeMonths, bestStreak: 2, coins: 0,
            adoptedOn: nil, today: CivilDay("2026-07-25")!
        )
        #expect(quarter.first { $0.id == "done" }?.title == "Done in 3 months")
    }
}

@Suite("Stats · memory rows")
struct StatsMemoryRowTests {

    @Test("each fact type renders its row; recovery stays digit-free")
    func rows() {
        let day = CivilDay("2026-06-21")!
        let facts = [
            CallbackFact(type: .dateEcho, factId: "completion-day-2026-06-25", sourceDay: CivilDay("2026-06-25")!, count: 6, monthsBack: 1),
            CallbackFact(type: .recovery, factId: "recovery-abc", sourceDay: day),
            CallbackFact(type: .bestDay, factId: "completion-day-2026-06-21", sourceDay: day, count: 9, tied: true),
            CallbackFact(type: .streakEra, factId: "streak-record-12-2026-05-01", sourceDay: CivilDay("2026-05-01")!, streakCount: 12, eraDated: true),
        ]
        let rows = StatsViewModel.memoryRows(facts: facts)
        #expect(rows.count == 4)
        #expect(rows[0].title == "One month ago today")
        #expect(rows[0].subtitle.contains("6 tasks"))
        #expect(rows[1].subtitle.rangeOfCharacter(from: .decimalDigits) == nil, "recovery copy carries no digits")
        #expect(rows[2].title == "One of your biggest days")
        #expect(rows[3].subtitle.contains("12 days"))
        #expect(rows[3].subtitle.contains("set"))
    }

    @Test("an undated streak era gets count-only copy, never a guessed date")
    func legacyEra() {
        let rows = StatsViewModel.memoryRows(facts: [
            CallbackFact(type: .streakEra, factId: "streak-record-8-legacy", sourceDay: CivilDay("2026-06-01")!, streakCount: 8, eraDated: false)
        ])
        #expect(rows[0].subtitle == "8 days")
    }
}

@Suite("Stats · list breakdown")
@MainActor
struct StatsListBreakdownTests {

    private let work = TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0)

    @Test("slices map listIds to names, bucket nil as Inbox, and sort by count")
    func slices() {
        let stats = [
            liveStat(daysAgo: 0, listId: "work"),
            liveStat(daysAgo: 0, listId: "work"),
            liveStat(daysAgo: 0, listId: nil),
        ]
        let slices = StatsViewModel.listSlices(stats: stats, lists: [work])
        #expect(slices.map(\.name) == ["Work", "Inbox"])
        #expect(slices.map(\.count) == [2, 1])
    }

    @Test("beyond the limit, the tail folds into a single Other slice")
    func otherFold() {
        let stats = (0..<7).flatMap { index in
            (0..<(7 - index)).map { _ in liveStat(daysAgo: 0, listId: "l\(index)") }
        }
        let lists = (0..<7).map {
            TaskList(id: "l\($0)", name: "List \($0)", colorHex: "#C9A6FF", icon: "tag.fill", order: $0)
        }
        let slices = StatsViewModel.listSlices(stats: stats, lists: lists, limit: 5)
        #expect(slices.count == 6)
        #expect(slices.last?.name == "Other")
        #expect(slices.last?.count == 2 + 1, "the two smallest lists fold together")
    }

    @Test("a completion whose list was deleted still shows, labeled as a former list")
    func deletedList() {
        let stats = [liveStat(daysAgo: 0, listId: "gone")]
        let slices = StatsViewModel.listSlices(stats: stats, lists: [])
        #expect(slices.first?.name == "Former list")
    }
}
