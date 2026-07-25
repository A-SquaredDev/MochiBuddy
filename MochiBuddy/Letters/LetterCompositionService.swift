//
//  LetterCompositionService.swift
//  MochiBuddy
//
//  The letter lifecycle orchestrator (Personal Layer, Feature 3). Runs on
//  every USER-VISIBLE foreground: stamps the current period's engagement
//  marker, then - if the previous closed period earned a letter and none
//  exists - composes it behind the online barrier: flush pending writes,
//  read server-backed state, compose purely, create transactionally.
//  If the create loses the race, the local result is discarded and the
//  winner displayed. Late is acceptable; wrong is not.
//
//  The notification is only ever an invitation - the letter becomes
//  available on the next eligible foreground regardless of permission
//  or delivery.
//

import Foundation
import Observation

@MainActor
@Observable
final class LetterCompositionService {

    /// The newest unread letter - drives the Home envelope indicator.
    private(set) var unreadLetter: Letter?

    /// Set by a letter-notification tap; Home consumes it to route
    /// straight to the letter with `source: .notification`.
    var pendingNotificationOpen: String?

    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private let profileRepository: UserProfileRepository
    @ObservationIgnored private let taskRepository: TaskRepository
    @ObservationIgnored private let listRepository: ListRepository
    @ObservationIgnored private let letterRepository: LetterRepository
    @ObservationIgnored private let observationLedger: ObservationLedger
    @ObservationIgnored private let membershipSession: MembershipSession
    @ObservationIgnored private let relay: NotificationRelaying?
    @ObservationIgnored private let telemetry: LetterTelemetry?

    /// Marker existence is checked at most once per period per launch.
    @ObservationIgnored private var markerEnsuredForPeriod: String?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        letterRepository: LetterRepository,
        observationLedger: ObservationLedger,
        membershipSession: MembershipSession,
        relay: NotificationRelaying? = nil,
        telemetry: LetterTelemetry? = nil
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.letterRepository = letterRepository
        self.observationLedger = observationLedger
        self.membershipSession = membershipSession
        self.relay = relay
        self.telemetry = telemetry
    }

    // MARK: - The foreground entry point

    /// Call ONLY from user-visible foreground paths (home entry, scene
    /// activation, notification tap) - never from background refresh,
    /// scheduling, or widget drains. That placement is what makes the
    /// activityWeeks marker a truthful dormancy arbiter.
    func handleUserForeground(now: Date = .now) async {
        guard let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId)
        else { return }

        let zone = authoritativeZone(for: profile)
        let bedtime = profile.bedtime

        // 1. The engagement marker for the CURRENT period, once per period.
        let current = LetterSchedule.period(containing: now, zone: zone, bedtime: bedtime)
        if markerEnsuredForPeriod != current.id {
            try? await letterRepository.ensureActivityMarker(periodId: current.id, userId: userId)
            markerEnsuredForPeriod = current.id
        }

        // 2. Refresh the unread indicator from the archive (cache-friendly).
        await refreshUnread(userId: userId)

        // 3. Compose the previous closed period if it earned a letter.
        await composeIfDue(userId: userId, profile: profile, now: now)
    }

    /// The planner's letter input (wired via the orchestrator's
    /// `letterInputProvider`): the CURRENT period's identity + cutoff,
    /// returned only once the period is already non-dormant - the
    /// scheduling invariant. Cache-friendly; runs on every re-lay.
    func plannedLetterInput(now: Date = .now) async -> LetterNotificationInput? {
        guard let userId = authRepository.currentAccount?.uid,
              !membershipSession.isLapsed,
              let profile = try? await profileRepository.fetchProfile(userId: userId),
              !profile.vacationActive(at: now)
        else { return nil }

        let zone = authoritativeZone(for: profile)
        let current = LetterSchedule.period(containing: now, zone: zone, bedtime: profile.bedtime)

        // No invitation before the first full post-adoption period.
        guard let adoptedOn = profile.adoptedOn,
              let firstEligible = LetterSchedule.firstEligiblePeriodStart(
                  adoptedOn: adoptedOn, zone: zone, bedtime: profile.bedtime
              ),
              current.start >= firstEligible
        else { return nil }

        // Non-dormant: a user-visible foreground this period (the marker)
        // or any completion inside the attribution window.
        var engaged = markerEnsuredForPeriod == current.id
        if !engaged {
            engaged = (try? await letterRepository.hasActivityMarker(
                periodId: current.id, userId: userId
            )) ?? false
        }
        if !engaged {
            let window = LetterSchedule.attributionWindow(
                of: current, zone: zone, bedtime: profile.bedtime
            )
            let stats = (try? await taskRepository.completedTaskStats(
                since: window.lowerBound, userId: userId
            )) ?? []
            engaged = stats.contains { window.contains($0.completedAt) }
        }
        guard engaged else { return nil }

        return LetterNotificationInput(
            periodStartDate: current.startDateString, fireAt: current.endExclusive
        )
    }

    /// Marks a letter read (synced; the one mutable field) and reports
    /// the open. Returns the classification-correct telemetry logging.
    func markOpened(_ letter: Letter, source: LetterOpenSource, now: Date = .now) async {
        guard let userId = authRepository.currentAccount?.uid else { return }
        let hasOpenedBefore = ((try? await letterRepository.letters(userId: userId)) ?? [])
            .contains { $0.readAt != nil && $0.id != letter.id }
        telemetry?.log(.opened(
            source: source,
            classification: letter.classification,
            timeToOpenBucket: LetterTelemetryBuckets.timeToOpen(
                composedAt: letter.composedAt, openedAt: now
            ),
            hasOpenedBefore: hasOpenedBefore
        ))
        if letter.isUnread {
            try? await letterRepository.markRead(letterId: letter.id, at: now, userId: userId)
        }
        await refreshUnread(userId: userId)
    }

    /// One letter by document id, from the cache-friendly archive - the
    /// notification-tap route resolves through here.
    func letter(id: String) async -> Letter? {
        guard let userId = authRepository.currentAccount?.uid else { return nil }
        return ((try? await letterRepository.letters(userId: userId)) ?? [])
            .first { $0.id == id }
    }

    func logShared(variant: String) {
        telemetry?.log(.shared(variant: variant))
    }

    func logIndicatorShown() {
        telemetry?.log(.indicatorShown)
    }

    #if DEBUG
    /// Dev inspector only: compose the previous closed period ignoring
    /// the dormancy / first-period / vacation / lapse gates, so the whole
    /// pipeline is verifiable without waiting for a real Sunday. The
    /// once-only existence contract still holds.
    func debugForceCompose(now: Date = .now) async -> String {
        guard let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId)
        else { return "no session" }
        let zone = authoritativeZone(for: profile)
        let period = LetterSchedule.previousClosedPeriod(at: now, zone: zone, bedtime: profile.bedtime)
        await composeIfDue(userId: userId, profile: profile, now: now, ignoringGates: true)
        let archive = (try? await letterRepository.letters(userId: userId)) ?? []
        return archive.contains { $0.id == period.id }
            ? "\(period.id) in archive"
            : "\(period.id) not composed (barrier failed?)"
    }
    #endif

    // MARK: - Composition

    private func composeIfDue(
        userId: String, profile: UserProfile, now: Date, ignoringGates: Bool = false
    ) async {
        // Lapsed: no letters, no backfill on return. Vacation: truly
        // silent - a period that closed just before the trip composes
        // late, on the first post-vacation foreground.
        guard ignoringGates || (!membershipSession.isLapsed && !profile.vacationActive(at: now)) else {
            return
        }

        let zone = authoritativeZone(for: profile)
        let candidate = LetterSchedule.previousClosedPeriod(at: now, zone: zone, bedtime: profile.bedtime)

        // First-period gate: the adoption week's partial period never
        // composes; day-1 delight is carried in-app.
        if !ignoringGates {
            guard let adoptedOn = profile.adoptedOn,
                  let firstEligible = LetterSchedule.firstEligiblePeriodStart(
                      adoptedOn: adoptedOn, zone: zone, bedtime: profile.bedtime
                  ),
                  candidate.start >= firstEligible
            else { return }
        }

        // Cheap existence check from cache before paying the barrier.
        if let cached = try? await letterRepository.letters(userId: userId),
           cached.contains(where: { $0.id == candidate.id }) {
            return
        }

        // --- The online barrier begins here. Every read below is
        // server-backed; failure means "try again next foreground".
        guard (try? await letterRepository.flushPendingWrites()) != nil,
              let serverProfile = try? await profileRepository.fetchProfileFromServer(userId: userId)
        else { return }

        // Re-derive the period from SERVER truth - the authoritative zone
        // is the synced one, never whichever zone this device is in.
        let serverZone = authoritativeZone(for: serverProfile)
        let period = LetterSchedule.previousClosedPeriod(
            at: now, zone: serverZone, bedtime: serverProfile.bedtime
        )
        let window = LetterSchedule.attributionWindow(
            of: period, zone: serverZone, bedtime: serverProfile.bedtime
        )

        guard let archive = try? await letterRepository.lettersFromServer(userId: userId) else {
            return
        }
        if archive.contains(where: { $0.id == period.id }) {
            await refreshUnread(userId: userId)
            return
        }

        // Dormancy: zero completions AND no user-visible foreground -
        // skip silently, never backfill, never "we missed you".
        let fetchStart = window.lowerBound.addingTimeInterval(-5 * 7 * 86_400)
        guard let stats = try? await taskRepository.completedTaskStatsFromServer(
                  since: fetchStart, userId: userId
              ),
              let completedTasks = try? await taskRepository.completedTasksFromServer(
                  since: window.lowerBound, userId: userId
              ),
              let incomplete = try? await taskRepository.incompleteTasksFromServer(userId: userId),
              let hadMarker = try? await letterRepository.hasActivityMarkerFromServer(
                  periodId: period.id, userId: userId
              )
        else { return }

        let periodStats = stats.filter { window.contains($0.completedAt) }
        guard ignoringGates || !periodStats.isEmpty || hadMarker else { return }

        // Vacation coverage from the synced interval log: fully-covered
        // periods compose nothing, ever.
        let coverage = PeriodSummaryBuilder.vacationCoverage(
            intervals: serverProfile.observationIntervals, window: window, now: now
        )
        guard ignoringGates || !coverage.fullyCovered else { return }

        let summary = await buildSummary(
            userId: userId,
            profile: serverProfile,
            period: period,
            window: window,
            zone: serverZone,
            stats: stats,
            periodStats: periodStats,
            completedTasks: completedTasks,
            incomplete: incomplete,
            archive: archive,
            hadMarker: hadMarker,
            now: now
        )

        let composed = LetterComposer.compose(summary: summary)
        let letter = Letter(
            id: period.id,
            periodStart: period.start,
            periodEndExclusive: period.endExclusive,
            timeZoneId: period.timeZoneId,
            classification: composed.classification,
            beatTypes: composed.beatTypes,
            lineIds: composed.lineIds,
            fullRenderedText: composed.fullText,
            privateRenderedText: composed.privateText,
            petNameSnapshot: summary.petName,
            composedAt: now,
            composerVersion: LetterConstants.composerVersion,
            copyDeckVersion: LetterCopy.version,
            periodSummaryHash: composed.summaryHash,
            readAt: nil
        )

        guard let stored = try? await letterRepository.createLetterIfAbsent(letter, userId: userId) else {
            return
        }
        if stored.composedAt == letter.composedAt, stored.periodSummaryHash == letter.periodSummaryHash {
            // Our create won: this is the one place a letter is born.
            telemetry?.log(.composed(
                classification: composed.classification,
                beatTypes: composed.beatTypes,
                wordBucket: LetterTelemetryBuckets.words(
                    composed.fullText.split(separator: " ").count
                )
            ))
            // The observation the letter used is consumed for the week
            // (same-week letter/rundown dedup).
            if let conclusion = summary.observationConclusion {
                observationLedger.recordSurfaced(
                    QualifiedObservation(
                        kind: kind(of: conclusion), conclusion: conclusion,
                        stableSince: period.startDateString
                    ),
                    surface: .letter,
                    on: CivilDay(of: now, in: LetterSchedule.calendar(for: serverZone)).dateString,
                    userId: userId
                )
            }
            relay?.requestRelay(.letterChange)
        }
        await refreshUnread(userId: userId)
    }

    // MARK: - Summary assembly

    private func buildSummary(
        userId: String,
        profile: UserProfile,
        period: LetterPeriod,
        window: Range<Date>,
        zone: TimeZone,
        stats: [CompletedTaskStat],
        periodStats: [CompletedTaskStat],
        completedTasks: [TaskItem],
        incomplete: [TaskItem],
        archive: [Letter],
        hadMarker: Bool,
        now: Date
    ) async -> PeriodSummary {
        // Trailing windows: the four attribution windows before this one.
        var trailingWindows: [Range<Date>] = []
        var cursor = period
        for _ in 0..<4 {
            let earlier = LetterSchedule.period(
                inWeekOf: cursor.start.addingTimeInterval(-3.5 * 86_400),
                zone: zone, bedtime: profile.bedtime
            )
            trailingWindows.append(LetterSchedule.attributionWindow(
                of: earlier, zone: zone, bedtime: profile.bedtime
            ))
            cursor = earlier
        }
        let firstEligible = profile.adoptedOn.flatMap {
            LetterSchedule.firstEligiblePeriodStart(
                adoptedOn: $0, zone: zone, bedtime: profile.bedtime
            )
        }

        // The insight beat: the highest-priority qualified observation
        // not already told this week; list return is its own beat.
        var observationConclusion: ObservationConclusion?
        var listReturnName: String?
        let observationInputs = ObservationEngine.Inputs(
            records: stats,
            intervals: profile.observationIntervals,
            logSince: profile.observationLogSince,
            knownListIds: Set(((try? await listRepository.fetchLists(userId: userId)) ?? []).map(\.id)),
            calendar: LetterSchedule.calendar(for: zone),
            now: now
        )
        let observationDay = CivilDay(of: now, in: LetterSchedule.calendar(for: zone)).dateString
        for qualified in ObservationEngine.evaluate(observationInputs).qualified {
            guard observationLedger.canSurfaceInLetter(qualified, on: observationDay, userId: userId) else {
                continue
            }
            if case .listReturn(let listId) = qualified.conclusion {
                let lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
                listReturnName = lists.first { $0.id == listId }?.name
            } else if observationConclusion == nil {
                observationConclusion = qualified.conclusion
            }
        }

        let coverage = PeriodSummaryBuilder.vacationCoverage(
            intervals: profile.observationIntervals, window: window, now: now
        )

        return PeriodSummary(
            periodId: period.id,
            petName: profile.mochiName,
            adoptedOn: profile.adoptedOn,
            completionCount: periodStats.count,
            tasksDueCount: PeriodSummaryBuilder.tasksDueCount(
                stats: periodStats, incomplete: incomplete, window: window
            ),
            overdueDayCount: PeriodSummaryBuilder.overdueDayCount(
                stats: periodStats, incomplete: incomplete, window: window, zone: zone
            ),
            trailingAverage: PeriodSummaryBuilder.trailingAverage(
                stats: stats, windows: trailingWindows, notBefore: firstEligible
            ),
            vacationOverlap: coverage.overlaps,
            bestDay: PeriodSummaryBuilder.bestDay(stats: periodStats),
            milestonesLanded: PeriodSummaryBuilder.milestonesLanded(
                stats: periodStats, window: window,
                streakCount: profile.streakCount,
                lastActiveDate: profile.lastActiveDate, zone: zone
            ),
            anniversary: PeriodSummaryBuilder.anniversary(
                adoptedOn: profile.adoptedOn, window: window,
                intervals: profile.observationIntervals, now: now, zone: zone
            ),
            comeback: PeriodSummaryBuilder.comeback(
                completedTasks: completedTasks, window: window, zone: zone
            ),
            observationConclusion: observationConclusion,
            listReturnName: listReturnName,
            hadUserForeground: hadMarker,
            priorLineIds: archive.prefix(2).flatMap(\.lineIds)
        )
    }

    // MARK: - Helpers

    private func authoritativeZone(for profile: UserProfile) -> TimeZone {
        profile.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    private func refreshUnread(userId: String) async {
        let archive = (try? await letterRepository.letters(userId: userId)) ?? []
        unreadLetter = archive.first(where: \.isUnread)
    }

    private func kind(of conclusion: ObservationConclusion) -> ObservationKind {
        switch conclusion {
        case .weekday: .weekday
        case .band: .timeOfDay
        case .momentumRising: .momentum
        case .listReturn: .listReturn
        case .comeback: .comeback
        }
    }
}
