//
//  JournalViewModel.swift
//  MochiBuddy
//
//  Assembles the Journal from artifacts the other features produced:
//  letters (by reference), moments, the gated observation set, and the
//  footer derivations inherited from the retired Stats module. No new
//  engines - the one derivation rule it owns is the lapse freeze:
//  everything evaluates at `effectiveNow = lapseStartedAt` while lapsed,
//  so the record stops moving instead of decaying toward zero.
//

import Foundation

final class JournalViewModel: ObservableStateViewModel<
    JournalBehavior.UIState,
    JournalBehavior.ViewAction,
    JournalBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let letterRepository: LetterRepository
    private let momentRepository: MomentRepository
    private let momentWriter: MomentWriter?
    private let observationService: ObservationService?
    private let observationLedger: ObservationLedger?
    private let membershipSession: MembershipSession
    private let petIdentityStore: PetIdentityStore
    private let letterService: LetterCompositionService?
    private let coordinator: TabCoordinator?
    private let telemetry: JournalTelemetry?
    private let calendar: Calendar

    private var letters: [Letter] = []
    /// Section impressions log once per Journal session (VM lifetime).
    private var loggedImpressions: Set<JournalSection> = []
    /// Journal-surfaced observation lines, stable per (conclusion, day) -
    /// the card keeps one phrasing per day instead of rotating the deck
    /// on every tab visit.
    private var surfacedLines: [String: String] = [:]

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        letterRepository: LetterRepository,
        momentRepository: MomentRepository,
        momentWriter: MomentWriter? = nil,
        observationService: ObservationService? = nil,
        observationLedger: ObservationLedger? = nil,
        membershipSession: MembershipSession,
        petIdentityStore: PetIdentityStore,
        letterService: LetterCompositionService? = nil,
        coordinator: TabCoordinator? = nil,
        telemetry: JournalTelemetry? = nil,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.letterRepository = letterRepository
        self.momentRepository = momentRepository
        self.momentWriter = momentWriter
        self.observationService = observationService
        self.observationLedger = observationLedger
        self.membershipSession = membershipSession
        self.petIdentityStore = petIdentityStore
        self.letterService = letterService
        self.coordinator = coordinator
        self.telemetry = telemetry
        self.calendar = calendar
        super.init(initialState: JournalBehavior.UIState())
    }

    override func triggerAsync(_ action: JournalBehavior.ViewAction) async {
        switch action {
        case .load:
            await load()
            await consumePendingRoute()

        case .heroTapped:
            if let id = uiState.hero?.letterId {
                openLetter(id: id, source: .archive)
            }

        case .letterTapped(let id):
            openLetter(id: id, source: .archive)

        case .sectionVisible(let section):
            guard !loggedImpressions.contains(section) else { return }
            loggedImpressions.insert(section)
            telemetry?.log(.sectionImpression(section))

        case .consumePendingRoute:
            await consumePendingRoute()
        }
    }

    // MARK: - Load

    private func load() async {
        defer { state.isLoading = false }
        guard let userId = authRepository.currentAccount?.uid else { return }
        let now = Date.now
        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let isLapsed = membershipSession.isLapsed

        // The freeze: while lapsed every derivation evaluates at the open
        // lapse interval's start - no live drift, no decay-to-zero. On
        // reactivation the interval closes and everything resumes live
        // over full retained history, lapse-period completions included.
        let lapseStart = profile?.observationIntervals.openInterval(.lapse)?.start
        let effectiveNow = isLapsed ? (lapseStart ?? now) : now

        letters = (try? await letterRepository.letters(userId: userId)) ?? []
        var moments = (try? await momentRepository.moments(userId: userId)) ?? []

        // Non-emptiness is structural (edge 2): adoptedOn with no adoption
        // document renders a synthesized row NOW and enqueues the
        // idempotent, legacy-safe repair write.
        if let adoptedOn = profile?.adoptedOn ?? petIdentityStore.adoptedOn,
           !moments.contains(where: { $0.type == .adoption }) {
            moments.append(MomentFactory.adoption(
                adoptedOn: adoptedOn, petName: nil, locale: .current, now: now
            ))
            await momentWriter?.ensureAdoptionMoment(adoptedOn: adoptedOn, now: now)
        }

        let petName = petIdentityStore.name
        let today = calendar.startOfDay(for: effectiveNow)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let trendStart = calendar.date(
            byAdding: .day, value: -(JournalTimeline.trendDays - 1), to: today
        ) ?? today
        // The cap is what makes the lapse freeze real: completions logged
        // after the pinned instant exist in the fetch but not the record.
        let stats = ((try? await taskRepository.completedTaskStats(since: trendStart, userId: userId)) ?? [])
            .filter { $0.completedAt <= effectiveNow }
        let weekStats = stats.filter { $0.completedAt >= weekStart }

        var next = uiState
        next.petName = petName
        next.isLapsed = isLapsed

        let nonAdoptionMoments = moments.contains { $0.type != .adoption }
        if letters.isEmpty, !nonAdoptionMoments, weekStats.isEmpty {
            // Young: the adoption beat carries the screen alone. No
            // charts, no observation card, no placeholders.
            let adoption = moments.first { $0.type == .adoption }
            next.young = adoption.map { moment in
                JournalBehavior.YoungState(
                    adoptionText: moment.renderedTextSnapshot,
                    dateLabel: AdoptedOnDate.displayString(moment.occurredOn) ?? moment.occurredOn
                )
            }
            next.headerSubtitle = isLapsed ? Self.lapsedSubtitle(petName: petName) : nil
            next.hero = nil
            next.months = []
            next.noticedLines = []
            next.footer = nil
            setUIState(next)
            return
        }
        next.young = nil

        // Hero: newest unread letter, excluded from the rows below while
        // promoted; older unread rows keep their trait in the timeline.
        let hero = letters.first(where: \.isUnread)
        next.hero = hero.map { letter in
            JournalBehavior.HeroLetter(
                letterId: letter.id,
                excerpt: JournalTimeline.excerpt(of: letter),
                dateLabel: JournalTimeline.dateLabel(JournalTimeline.letterDateString(letter))
            )
        }

        next.months = JournalTimeline.monthGroups(
            letters: letters,
            moments: moments,
            excludingLetterId: hero?.id,
            currentYear: calendar.component(.year, from: now)
        )

        next.headerSubtitle = isLapsed
            ? Self.lapsedSubtitle(petName: petName)
            : Self.sinceSubtitle(
                petName: petName,
                adoptedOn: profile?.adoptedOn ?? petIdentityStore.adoptedOn,
                currentYear: calendar.component(.year, from: now)
            )

        next.noticedLines = await noticedLines(
            userId: userId, petName: petName, isLapsed: isLapsed, effectiveNow: effectiveNow
        )

        // The record footer - only once the strip window holds at least
        // one completion (edge 13). The trend row needs two distinct
        // weeks of history; best streak omits at zero. No coins, no
        // on-time percentage, no busiest-weekday - record vs. grade.
        if weekStats.isEmpty {
            next.footer = nil
        } else {
            let bestStreak = profile?.bestStreakCount ?? 0
            next.footer = JournalBehavior.Footer(
                title: isLapsed ? "The week you paused" : "This week",
                week: JournalTimeline.weekCells(stats: weekStats, weekStart: weekStart, calendar: calendar),
                doneLabel: isLapsed ? "Done that week" : "Done this week",
                doneCount: weekStats.count,
                bestStreak: bestStreak > 0 ? bestStreak : nil,
                trend: JournalTimeline.trendQualifies(stats: stats, calendar: calendar)
                    ? JournalTimeline.trendPoints(stats: stats, start: trendStart, calendar: calendar)
                    : []
            )
        }

        setUIState(next)
    }

    /// The observation card's lines. Live: qualified conclusions surface
    /// through Feature 4's own bookkeeping (observation_shown, list-return
    /// event log), one stable phrasing per day. Lapsed: the engine
    /// re-derives at the pinned instant and lines render via the
    /// non-rotating peek - frozen, nothing composes, nothing advances.
    private func noticedLines(
        userId: String, petName: String, isLapsed: Bool, effectiveNow: Date
    ) async -> [String] {
        guard let observationService, let observationLedger,
              let inputs = await observationService.engineInputs(now: effectiveNow, calendar: calendar)
        else { return [] }
        let qualified = ObservationEngine.evaluate(inputs).qualified
        guard !qualified.isEmpty else { return [] }

        let lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        let civilDay = CivilDay(of: effectiveNow, in: calendar)
        let day = civilDay.dateString

        var lines: [String] = []
        for observation in qualified.prefix(3) {
            var listName: String?
            if case .listReturn(let listId) = observation.conclusion {
                listName = lists.first { $0.id == listId }?.name
            }
            let cacheKey = "\(ObservationLedger.conclusionKey(observation.conclusion))|\(day)"
            let line: String?
            if let cached = surfacedLines[cacheKey] {
                line = cached
            } else if isLapsed {
                line = observationLedger.peekLine(
                    for: observation.conclusion, petName: petName, listName: listName, userId: userId
                )
            } else if observation.kind == .momentum,
                      observationLedger.momentumCoolingDown(on: civilDay, userId: userId) {
                // The cooldown this card's own surfacing starts must also
                // govern the card: re-recording on every visit would push
                // lastSurfaced forward daily and starve rundowns and
                // letters of momentum forever. On the day it surfaced the
                // line stays visible via the non-rotating peek; on later
                // cooldown days momentum rests here like everywhere else.
                guard observationLedger.lastSurfacedDay(
                    of: observation.conclusion, userId: userId
                ) == day else { continue }
                line = observationLedger.peekLine(
                    for: observation.conclusion, petName: petName, listName: listName, userId: userId
                )
            } else {
                line = observationService.surfaced(
                    observation, surface: .journal, petName: petName,
                    listName: listName, now: effectiveNow, calendar: calendar
                )
                if let line { surfacedLines[cacheKey] = line }
            }
            if let line {
                lines.append(line)
            }
        }
        return lines
    }

    // MARK: - Header copy

    /// Full localized format strings - possessive/relational phrasing is
    /// per-locale, never concatenated (the Feature 1 rule extended).
    static func sinceSubtitle(petName: String, adoptedOn: String?, currentYear: Int) -> String? {
        guard let adoptedOn, CivilDay(adoptedOn) != nil else { return nil }
        let label = JournalTimeline.monthTitle(String(adoptedOn.prefix(7)), currentYear: currentYear)
        return String(format: "With %@ since %@", petName, label)
    }

    static func lapsedSubtitle(petName: String) -> String {
        String(format: "%@ is napping · paused", petName)
    }

    // MARK: - Letter routing

    private func openLetter(id: String, source: LetterOpenSource) {
        guard let letter = letters.first(where: { $0.id == id }) else { return }
        setNavigationEvent(.openLetter(letter, source))
    }

    /// A pending envelope/notification route - the coordinator held it
    /// through the tab switch; the Journal resolves the stable id and
    /// pushes the detail.
    private func consumePendingRoute() async {
        guard let route = coordinator?.consumePendingLetterRoute() else { return }
        var letter = letters.first { $0.id == route.letterId }
        if letter == nil {
            letter = await letterService?.letter(id: route.letterId)
        }
        guard let letter else { return }
        setNavigationEvent(.openLetter(
            letter, route.source == .envelope ? .home : .notification
        ))
    }
}
