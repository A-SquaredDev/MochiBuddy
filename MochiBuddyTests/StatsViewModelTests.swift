//
//  StatsViewModelTests.swift
//  MochiBuddyTests
//
//  The chart derivations: 4-week trend fill, on-time math, busiest
//  weekday, rhythm bands, tiles, memory rows, and the per-list breakdown.
//  Fixture dates anchor to the REAL clock (the VM reads Date.now), same
//  doctrine as JournalTests.
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
    listId: String? = nil
) -> CompletedTaskStat {
    let instant = daysAgo(d).addingTimeInterval(TimeInterval(minuteOfDay * 60))
    return CompletedTaskStat(
        taskId: UUID().uuidString,
        seriesId: nil,
        completedAt: instant,
        dueAt: dueAt,
        listId: listId,
        hasTime: false,
        isRecurring: false,
        source: .mochi,
        rescheduleCount: 0,
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
        #expect(trend.count == StatsViewModel.trendDays)
        #expect(trend.last?.count == 2, "today is the last point")
        #expect(trend[trend.count - 4].count == 1, "three days ago")
        #expect(trend.map(\.count).reduce(0, +) == 3, "every other day is zero")
    }

    @Test("week tiles only count the last 7 days even though the fetch spans 28")
    func weekTilesSliceSeven() async {
        let stats = [
            liveStat(daysAgo: 1),
            liveStat(daysAgo: 10),
            liveStat(daysAgo: 20),
        ]
        let vm = makeStatsVM(stats: stats)
        await vm.triggerAsync(.load)
        let doneTile = vm.uiState.tiles.first { $0.id == "done" }
        #expect(doneTile?.value == "1")
        #expect(vm.uiState.trend.map(\.count).reduce(0, +) == 3)
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

    @Test("busiest weekday names the weekday with the most completions, pluralized")
    func busiestWeekday() {
        // Two completions on today's weekday, one on yesterday's.
        let stats = [
            liveStat(daysAgo: 0),
            liveStat(daysAgo: 7),
            liveStat(daysAgo: 1),
        ]
        let expected = calendar.standaloneWeekdaySymbols[calendar.component(.weekday, from: startOfToday) - 1] + "s"
        #expect(StatsViewModel.busiestWeekday(stats: stats, calendar: calendar) == expected)
        #expect(StatsViewModel.busiestWeekday(stats: [], calendar: calendar) == nil)
    }
}

@Suite("Stats · rhythm bands")
struct StatsRhythmTests {

    @Test("completions bucket into their local-minute band, zero-filled in fixed order")
    func bandBuckets() {
        let stats = [
            liveStat(daysAgo: 1, minuteOfDay: 6 * 60),        // morning
            liveStat(daysAgo: 2, minuteOfDay: 19 * 60),       // evening
            liveStat(daysAgo: 3, minuteOfDay: 19 * 60 + 30),  // evening
            liveStat(daysAgo: 4, minuteOfDay: 23 * 60),       // night
        ]
        let bars = StatsViewModel.bandBars(stats: stats)
        #expect(bars.map(\.label) == ["Morning", "Afternoon", "Evening", "Night"])
        #expect(bars.map(\.count) == [1, 0, 2, 1])
        #expect(StatsViewModel.bandBars(stats: []).isEmpty)
    }

    @Test("the caption names the top band; silence when everything is zero")
    func caption() {
        let bars = StatsViewModel.bandBars(stats: [liveStat(daysAgo: 1, minuteOfDay: 19 * 60)])
        #expect(StatsViewModel.rhythmCaption(bars: bars) == "Evenings do the heavy lifting")
        #expect(StatsViewModel.rhythmCaption(bars: []) == nil)
    }
}

@Suite("Stats · tiles")
struct StatsTilesTests {

    @Test("with an adoption date the fourth tile counts days together, adoption day inclusive")
    func daysTogether() {
        let today = CivilDay("2026-07-25")!
        let tiles = StatsViewModel.tiles(
            weekDone: 4, weekOnTime: "80%", bestStreak: 9, coins: 40,
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
            weekDone: 0, weekOnTime: "–", bestStreak: 1, coins: 40,
            adoptedOn: nil, today: CivilDay("2026-07-25")!
        )
        #expect(tiles.contains { $0.id == "coins" && $0.value == "40" })
        let best = tiles.first { $0.id == "best" }
        #expect(best?.subtitle == "day", "singular at 1")
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
