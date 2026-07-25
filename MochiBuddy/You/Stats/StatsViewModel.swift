//
//  StatsViewModel.swift
//  MochiBuddy
//
//  Streaks & stats - gentle momentum, not a scoreboard. Week strip and
//  charts come from completed-task timestamps; streak/coins from the
//  profile; the noticed lines and memory rows ride the Personal Layer's
//  existing engines (Features 4 and 2) without advancing their cadence.
//

import SwiftUI

final class StatsViewModel: StateViewModel<
    StatsBehavior.UIState,
    StatsBehavior.ViewAction
> {

    /// The charts read four weeks of completions.
    static let trendDays = JournalTimeline.trendDays

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let petIdentityStore: PetIdentityStore
    private let observationService: ObservationService?
    private let observationLedger: ObservationLedger?
    private let calendar: Calendar

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        petIdentityStore: PetIdentityStore,
        observationService: ObservationService? = nil,
        observationLedger: ObservationLedger? = nil,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.petIdentityStore = petIdentityStore
        self.observationService = observationService
        self.observationLedger = observationLedger
        self.calendar = calendar
        super.init(initialState: StatsBehavior.UIState())
    }

    override func triggerAsync(_ action: StatsBehavior.ViewAction) async {
        switch action {
        case .load:
            await load()
        }
    }

    private func load() async {
        guard let userId = authRepository.currentAccount?.uid else { return }
        let now = Date.now

        var next = uiState
        next.petName = petIdentityStore.name

        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let streak = profile?.streakCount ?? 0
        let bestStreak = profile?.bestStreakCount ?? 0
        next.coins = profile?.coins ?? 0
        next.streakText = "\(streak) day\(streak == 1 ? "" : "s")"
        next.streakSub = streak > 0
            ? "Keep it going, a task a day does it"
            : "A task a day starts one"

        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let trendStart = calendar.date(byAdding: .day, value: -(Self.trendDays - 1), to: today) ?? today

        // One 4-week fetch feeds every chart; week widgets slice the last 7.
        let stats = (try? await taskRepository.completedTaskStats(since: trendStart, userId: userId)) ?? []
        let weekStats = stats.filter { $0.completedAt >= weekStart }
        let lists = (try? await listRepository.fetchLists(userId: userId)) ?? []

        next.week = JournalTimeline.weekCells(stats: weekStats, weekStart: weekStart, calendar: calendar)
        next.tiles = Self.tiles(
            weekDone: weekStats.count,
            weekOnTime: Self.onTimeText(weekStats),
            bestStreak: bestStreak,
            coins: next.coins,
            adoptedOn: profile?.adoptedOn ?? petIdentityStore.adoptedOn,
            today: CivilDay(of: now, in: calendar)
        )

        next.trend = stats.isEmpty
            ? []
            : JournalTimeline.trendPoints(stats: stats, start: trendStart, calendar: calendar)
        next.trendCaption = stats.isEmpty
            ? nil
            : "\(Self.onTimeText(stats)) on time · busiest on \(Self.busiestWeekday(stats: stats, calendar: calendar) ?? "–")"

        next.rhythm = Self.bandBars(stats: stats)
        next.rhythmCaption = Self.rhythmCaption(bars: next.rhythm)
        next.listBreakdown = Self.listSlices(stats: stats, lists: lists)

        next.noticedLines = await noticedLines(
            userId: userId, petName: next.petName, lists: lists, now: now
        )
        next.memoryRows = Self.memoryRows(facts: await Self.minedFacts(
            profile: profile, observationService: observationService, now: now, calendar: calendar
        ))

        setUIState(next)
    }

    // MARK: - Personal Layer readers

    /// Qualified observations rendered through the non-rotating peek -
    /// a read-only surface never advances rotation or cadence state
    /// (the Journal's live card owns that bookkeeping).
    private func noticedLines(
        userId: String, petName: String, lists: [TaskList], now: Date
    ) async -> [String] {
        guard let observationService, let observationLedger,
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return [] }
        let qualified = ObservationEngine.evaluate(inputs).qualified
        return qualified.prefix(3).compactMap { observation in
            var listName: String?
            if case .listReturn(let listId) = observation.conclusion {
                listName = lists.first { $0.id == listId }?.name
            }
            return observationLedger.peekLine(
                for: observation.conclusion, petName: petName, listName: listName, userId: userId
            )
        }
    }

    private static func minedFacts(
        profile: UserProfile?,
        observationService: ObservationService?,
        now: Date,
        calendar: Calendar
    ) async -> [CallbackFact] {
        guard let profile, let observationService,
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return [] }
        let miner = CallbackMinerInputs(
            records: inputs.records,
            adoptedOn: profile.adoptedOn,
            streakCount: profile.streakCount,
            bestStreakCount: profile.bestStreakCount,
            bestStreakAchievedOn: profile.bestStreakAchievedOn,
            lastActiveDay: profile.lastActiveDate.map { CivilDay(of: $0, in: calendar) }
        )
        return CallbackFactMiner.facts(miner, on: CivilDay(of: now, in: calendar))
    }

    // MARK: - Derivations (pure, testable)

    static func tiles(
        weekDone: Int,
        weekOnTime: String,
        bestStreak: Int,
        coins: Int,
        adoptedOn: String?,
        today: CivilDay
    ) -> [StatsBehavior.StatTile] {
        var tiles: [StatsBehavior.StatTile] = [
            .init(id: "done", value: "\(weekDone)", title: "Done this week", subtitle: "tasks"),
            .init(id: "completion", value: weekOnTime, title: "On time", subtitle: "this week"),
            .init(id: "best", value: "\(bestStreak)", title: "Best streak", subtitle: bestStreak == 1 ? "day" : "days"),
        ]
        // The fourth tile prefers the friendship; coins fill in until an
        // adoption date exists (pre-Feature-1 profiles).
        if let adoptedOn, let adopted = CivilDay(adoptedOn), adopted <= today {
            let days = today.dayNumber - adopted.dayNumber + 1
            tiles.append(.init(
                id: "together", value: "\(days)", title: days == 1 ? "Day together" : "Days together",
                subtitle: "since \(shortDate(adopted))"
            ))
        } else {
            tiles.append(.init(id: "coins", value: "\(coins)", title: "Coins", subtitle: "balance"))
        }
        return tiles
    }

    static func onTimeText(_ stats: [CompletedTaskStat]) -> String {
        guard !stats.isEmpty else { return "–" }
        // No due date counts as on time - undated tasks can't be late.
        let onTime = stats.filter { stat in
            guard let due = stat.dueAt else { return true }
            return stat.completedAt <= due
        }.count
        return "\(Int((Double(onTime) / Double(stats.count) * 100).rounded()))%"
    }

    static func busiestWeekday(stats: [CompletedTaskStat], calendar: Calendar) -> String? {
        guard !stats.isEmpty else { return nil }
        var countsByWeekday: [Int: Int] = [:]
        for stat in stats {
            countsByWeekday[calendar.component(.weekday, from: stat.completedAt), default: 0] += 1
        }
        guard let busiest = countsByWeekday.max(by: {
            ($0.value, $1.key) < ($1.value, $0.key) // ties break to the earlier weekday
        })?.key else { return nil }
        return calendar.standaloneWeekdaySymbols[busiest - 1] + "s"
    }

    /// Completion counts per time-of-day band, in the completion's own
    /// zone (the local minute each record carries), zero-filled.
    static func bandBars(stats: [CompletedTaskStat]) -> [StatsBehavior.BandBar] {
        guard !stats.isEmpty else { return [] }
        var counts: [TimeOfDayBand: Int] = [:]
        for stat in stats {
            counts[TimeOfDayBand(minute: stat.completedLocalMinute), default: 0] += 1
        }
        let order: [(TimeOfDayBand, String)] = [
            (.morning, "Morning"), (.afternoon, "Afternoon"),
            (.evening, "Evening"), (.night, "Night"),
        ]
        return order.map { band, label in
            .init(id: band.rawValue, label: label, count: counts[band] ?? 0)
        }
    }

    static func rhythmCaption(bars: [StatsBehavior.BandBar]) -> String? {
        guard let top = bars.max(by: { $0.count < $1.count }), top.count > 0 else { return nil }
        switch top.id {
        case TimeOfDayBand.morning.rawValue: return "Mornings do the heavy lifting"
        case TimeOfDayBand.afternoon.rawValue: return "Afternoons do the heavy lifting"
        case TimeOfDayBand.evening.rawValue: return "Evenings do the heavy lifting"
        default: return "The late hours do the heavy lifting"
        }
    }

    static func listSlices(
        stats: [CompletedTaskStat],
        lists: [TaskList],
        limit: Int = 5
    ) -> [StatsBehavior.ListSlice] {
        guard !stats.isEmpty else { return [] }
        var countsByList: [String?: Int] = [:]
        for stat in stats {
            countsByList[stat.listId, default: 0] += 1
        }
        let slices = countsByList
            .map { listId, count -> StatsBehavior.ListSlice in
                if let listId, let list = lists.first(where: { $0.id == listId }) {
                    return .init(id: listId, name: list.name, color: Color(hexString: list.colorHex), count: count)
                }
                // Unknown ids (deleted lists) fold into the Inbox slice's look.
                return .init(
                    id: listId ?? "inbox",
                    name: listId == nil ? "Inbox" : "Former list",
                    color: Color(hexString: TaskListDefaults.colorChoices[0]),
                    count: count
                )
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        guard slices.count > limit else { return slices }
        let top = Array(slices.prefix(limit))
        let otherCount = slices.dropFirst(limit).reduce(0) { $0 + $1.count }
        return top + [.init(id: "other", name: "Other", color: .gray, count: otherCount)]
    }

    /// Mined facts as factual rows. Counts appear only in the families
    /// that permit them (best day, date echo); recovery stays digit-free
    /// by the same rule its rundown copy follows.
    static func memoryRows(facts: [CallbackFact]) -> [StatsBehavior.MemoryRow] {
        facts.compactMap { fact in
            switch fact.type {
            case .dateEcho:
                return .init(
                    id: fact.factId,
                    icon: "calendar",
                    title: fact.monthsBack == 1
                        ? "One month ago today"
                        : "\(fact.monthsBack) months ago today",
                    subtitle: "\(fact.count) task\(fact.count == 1 ? "" : "s") done on \(shortDate(fact.sourceDay))"
                )
            case .recovery:
                return .init(
                    id: fact.factId,
                    icon: "arrow.uturn.up",
                    title: "A quick comeback",
                    subtitle: "Slipped things got caught up in a hurry"
                )
            case .bestDay:
                return .init(
                    id: fact.factId,
                    icon: "sparkles",
                    title: fact.tied ? "One of your biggest days" : "Your biggest day yet",
                    subtitle: "\(fact.count) task\(fact.count == 1 ? "" : "s") on \(shortDate(fact.sourceDay))"
                )
            case .streakEra:
                return .init(
                    id: fact.factId,
                    icon: "flame.fill",
                    title: "Longest streak",
                    subtitle: fact.eraDated
                        ? "\(fact.streakCount) days · set \(shortDate(fact.sourceDay))"
                        : "\(fact.streakCount) days"
                )
            }
        }
    }

    /// "Jul 8" (or "Jul 8, 2025" once the year differs) from a civil day -
    /// zone-free, same doctrine as AdoptedOnDate's display.
    static func shortDate(_ day: CivilDay, today: CivilDay = CivilDay(of: .now, in: .current)) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        let anchor = Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
        let sameYear = utc.component(.year, from: anchor)
            == utc.component(.year, from: Date(timeIntervalSince1970: TimeInterval(today.dayNumber) * 86_400 + 43_200))
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: anchor)
    }
}
