//
//  MemoriesService.swift
//  MochiBuddy
//
//  The thin orchestrator for anniversaries and memory callbacks
//  (Personal Layer, Feature 2). Assembles the pure planner's inputs
//  (facts from the same 132-day fetch Feature 4 already makes - no new
//  query), commits assignments to the CallbackLedger idempotently, and
//  posts the anniversary banner on the day's first open.
//
//  Lapsed: the notification planner lays no rundowns and this service
//  skips the banner outright - anniversaries are never backdated, and
//  "you missed our anniversary" on resubscribe is guilt manufacturing.
//

import Foundation

/// The one Personal-Layer line for a rundown morning, ready to dress:
/// the semantic line plus its rendered opener (nil for the
/// crushed-yesterday title override).
struct PersonalLayerContent: Equatable {
    let line: PersonalLayerLine
    let opener: String?
}

/// What the request builder knows about a rundown's Personal-Layer slot.
/// `.none` is a real decision (the planner ran and the day carries
/// nothing - e.g. a streak-claimed date); `.unavailable` means no
/// planner ran at all, so the legacy crushed-yesterday computation
/// applies as the fallback.
enum PersonalLayerSlot: Equatable {
    case unavailable
    case none
    case line(PersonalLayerContent)
}

@MainActor
final class MemoriesService {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let observationService: ObservationService
    private let observationLedger: ObservationLedger
    private let ledger: CallbackLedger
    private let membershipSession: MembershipSession
    private let celebrationCenter: CelebrationCenter
    private let momentWriter: MomentWriter?
    private let telemetry: CallbackTelemetry?
    private let calendar: Calendar

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        observationService: ObservationService,
        observationLedger: ObservationLedger,
        ledger: CallbackLedger,
        membershipSession: MembershipSession,
        celebrationCenter: CelebrationCenter,
        momentWriter: MomentWriter? = nil,
        telemetry: CallbackTelemetry? = nil,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.observationService = observationService
        self.observationLedger = observationLedger
        self.ledger = ledger
        self.membershipSession = membershipSession
        self.celebrationCenter = celebrationCenter
        self.momentWriter = momentWriter
        self.telemetry = telemetry
        self.calendar = calendar
    }

    // MARK: - Rundown assignment (called from every re-lay)

    /// Choose at most one Personal-Layer line per planned rundown and
    /// commit the cadence consequences. Deterministic per relay: same
    /// inputs produce the same assignment, so an unchanged morning
    /// keeps its stored line and consumes nothing twice.
    func assignPersonalLayer(
        rundowns: [PlannedNotification],
        snapshot: MoodSnapshot,
        taper: TaperState,
        completionTimes: [Date],
        now: Date
    ) async -> [String: PersonalLayerContent] {
        guard !membershipSession.isLapsed,
              let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId),
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return [:] }

        let today = CivilDay(of: now, in: calendar)
        let miner = CallbackMinerInputs(
            records: inputs.records,
            adoptedOn: profile.adoptedOn,
            streakCount: profile.streakCount,
            bestStreakCount: profile.bestStreakCount,
            bestStreakAchievedOn: profile.bestStreakAchievedOn,
            lastActiveDay: profile.lastActiveDate.map { CivilDay(of: $0, in: calendar) }
        )
        let observations = ObservationEngine.evaluate(inputs).qualified
        let lastActiveDay = miner.lastActiveDay

        // Journal record (Feature 6): a qualified list-return event earns
        // its moment here, on the layer's most reliable evaluation beat.
        // Once-per-event is the moment's own natural key; the ledger's
        // surfacing cadence is not consulted - the event happened.
        for observation in observations where observation.kind == .listReturn {
            await momentWriter?.listReturn(observation, now: now)
        }

        let days: [PersonalLayerPlanner.DayContext] = rundowns
            .filter { $0.kind == .rundown }
            .map { plan in
                let day = CivilDay(of: plan.fireAt, in: calendar)
                return PersonalLayerPlanner.DayContext(
                    day: day,
                    fireAt: plan.fireAt,
                    register: RundownEmotionalRegister.evaluate(
                        fireAt: plan.fireAt, snapshot: snapshot, taper: taper, calendar: calendar
                    ),
                    crushedYesterday: crushedYesterday(
                        before: plan.fireAt, completionTimes: completionTimes
                    ),
                    deferredAcknowledgment: AnniversaryCalendar.deferredAcknowledgment(
                        adoptedOn: profile.adoptedOn,
                        intervals: profile.observationIntervals,
                        wake: plan.fireAt,
                        previousWake: plan.fireAt.addingTimeInterval(-24 * 3600),
                        calendar: calendar
                    ),
                    streakClaimed: PersonalLayerPlanner.streakClaims(
                        day: day, streakCount: profile.streakCount, lastActiveDay: lastActiveDay
                    )
                )
            }

        let fireAtByDate = Dictionary(
            days.map { ($0.day.dateString, $0.fireAt) },
            uniquingKeysWith: { a, _ in a }
        )

        var state = ledger.state(userId: userId)
        let assignments = PersonalLayerPlanner.assign(
            days: days,
            miner: miner,
            observations: observations,
            ledger: state,
            canSurfaceObservation: { [observationLedger] observation, day in
                observationLedger.canSurfaceInRundown(
                    observation, on: day.dateString, userId: userId
                )
            }
        )
        let byDate = Dictionary(
            assignments.map { ($0.day.dateString, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        let changed = CallbackLedger.fold(
            assignments: byDate.mapValues(\.line.ledgerValue),
            today: today,
            into: &state
        )

        // Render + log ONCE per actual change, never once per relay.
        for (date, _) in changed.sorted(by: { $0.key < $1.key }) {
            guard let assignment = byDate[date] else { continue }
            switch assignment.line {
            case .crushedYesterday:
                break
            case .anniversary(let milestone):
                state.rendered[date] = MemoriesCopy.rundownOpenerTemplate(
                    for: assignment.line, today: assignment.day, deck: &state.deck
                )
                telemetry?.log(.anniversaryShown(
                    tier: milestone.tier.telemetryLabel, surface: "rundown"
                ))
            case .deferredAnniversary(let milestone):
                state.rendered[date] = MemoriesCopy.rundownOpenerTemplate(
                    for: assignment.line, today: assignment.day, deck: &state.deck
                )
                telemetry?.log(.anniversaryShown(
                    tier: milestone.tier.telemetryLabel, surface: "deferred"
                ))
            case .callback(let fact):
                state.rendered[date] = MemoriesCopy.rundownOpenerTemplate(
                    for: assignment.line, today: assignment.day, deck: &state.deck
                )
                telemetry?.log(.callbackShown(type: fact.type, register: assignment.register))
            case .observation(let observation):
                // Feature 4's own bookkeeping: weekly cap, same-week
                // dedup, copy rotation, observation_shown. Passing the
                // placeholder as the name keeps the stored line a {name}
                // template, same as every other opener.
                state.rendered[date] = observationService.surfaced(
                    observation, surface: .rundown,
                    petName: PetCopyTemplate.namePlaceholder,
                    now: fireAtByDate[date] ?? now,
                    calendar: calendar
                )
            }
        }

        logEvaluations(
            miner: miner, today: today,
            register: RundownEmotionalRegister.evaluate(
                fireAt: now, snapshot: snapshot, taper: taper, calendar: calendar
            ),
            selectedToday: byDate[today.dateString],
            state: &state
        )

        ledger.save(state, userId: userId)

        return byDate.compactMapValues { assignment in
            PersonalLayerContent(
                line: assignment.line,
                opener: state.rendered[assignment.day.dateString].map {
                    PetCopyTemplate.render($0, petName: profile.mochiName)
                }
            )
        }
    }

    private func crushedYesterday(before fireAt: Date, completionTimes: [Date]) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: fireAt) else {
            return false
        }
        let count = completionTimes.count { calendar.isDate($0, inSameDayAs: yesterday) }
        return count >= NotificationCopy.crushedYesterdayThreshold
    }

    // MARK: - The denominator

    /// callback_evaluated, at most once per type per user-day: the
    /// mining-level reason, upgraded to the selection-level reason where
    /// the day's slot decided the outcome.
    private func logEvaluations(
        miner: CallbackMinerInputs,
        today: CivilDay,
        register: RundownEmotionalRegister,
        selectedToday: PersonalLayerPlanner.Assignment?,
        state: inout CallbackLedger.State
    ) {
        guard let telemetry else { return }
        let evaluations = CallbackFactMiner.evaluate(miner, on: today)
        let selectedFact: CallbackFact? = if case .callback(let fact)? = selectedToday?.line {
            fact
        } else {
            nil
        }

        for evaluation in evaluations {
            guard state.lastEvaluated[evaluation.type.rawValue] != today.dateString else { continue }
            state.lastEvaluated[evaluation.type.rawValue] = today.dateString

            var qualified = false
            var blocked = evaluation.blocked
            if let fact = evaluation.fact {
                if selectedFact?.factId == fact.factId {
                    qualified = true
                    blocked = nil
                } else if !register.admits(fact.type) {
                    blocked = .register
                } else if state.consumedFactIds.contains(fact.factId) {
                    blocked = .alreadyTold
                } else if state.callbackCount(inWeekOf: today) >= CallbackConstants.weeklyCap {
                    blocked = .weeklyCap
                } else if let gap = state.nearestCallbackGap(to: today),
                          gap < CallbackConstants.minGapDays {
                    blocked = .gap
                } else {
                    // Qualified but a higher line (or higher type) took
                    // the slot - priority starvation, made visible.
                    blocked = .priority
                }
            }
            telemetry.log(.callbackEvaluated(
                type: evaluation.type,
                qualified: qualified,
                register: register,
                blocked: blocked
            ))
        }
    }

    // MARK: - Anniversary banner (day's first open)

    /// Post today's anniversary to the CelebrationCenter, once per
    /// milestone, unless a streak milestone owns the date (the general
    /// same-date collision rule) or vacation/lapse holds the silence.
    /// Notifications denied never matters here - this is the in-app
    /// surface that carries the anniversary regardless (a date is not a
    /// demand, and the register never gates it either).
    func checkAnniversaryBanner(now: Date = .now) async {
        guard !membershipSession.isLapsed,
              let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId),
              !profile.vacationActive(at: now)
        else { return }

        let today = CivilDay(of: now, in: calendar)
        guard let milestone = AnniversaryCalendar.milestone(
            adoptedOn: profile.adoptedOn, on: today
        ) else { return }

        // Journal record (Feature 6): written on detection, BEFORE the
        // banner's dedup and collision suppression - a streak milestone
        // may own the banner, but the day still happened. Idempotent by
        // natural key.
        await momentWriter?.anniversary(milestone, now: now)

        var state = ledger.state(userId: userId)
        guard state.bannerShown[milestone.id] == nil else { return }

        // Streak owns the day on a same-date collision - suppressed here,
        // remembered by the letter.
        let lastActiveDay = profile.lastActiveDate.map { CivilDay(of: $0, in: calendar) }
        guard !PersonalLayerPlanner.streakClaims(
            day: today, streakCount: profile.streakCount, lastActiveDay: lastActiveDay
        ) else { return }

        let text = MemoriesCopy.bannerText(
            for: milestone, petName: profile.mochiName, deck: &state.deck
        )
        state.bannerShown[milestone.id] = today.dateString
        // Only the newest few marks matter; the map stays tiny.
        if state.bannerShown.count > 8 {
            let sorted = state.bannerShown.sorted { $0.value < $1.value }
            for (key, _) in sorted.dropLast(8) {
                state.bannerShown.removeValue(forKey: key)
            }
        }
        ledger.save(state, userId: userId)

        celebrationCenter.post(anniversaryText: text)
        telemetry?.log(.anniversaryShown(tier: milestone.tier.telemetryLabel, surface: "banner"))
    }

    /// Account deletion rides the same erase path as the observation
    /// ledger.
    func clear(userId: String) {
        ledger.clear(userId: userId)
    }

    #if DEBUG
    /// The dev inspector's raw material - fetched once per rebuild, then
    /// re-evaluated synchronously as the time-travel slider moves (the
    /// miner is pure, so shifting "now" on cached inputs is sound).
    func inspectorInputs(now: Date) async -> DevMemoriesInspector.Inputs? {
        guard let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId),
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return nil }
        return DevMemoriesInspector.Inputs(
            miner: CallbackMinerInputs(
                records: inputs.records,
                adoptedOn: profile.adoptedOn,
                streakCount: profile.streakCount,
                bestStreakCount: profile.bestStreakCount,
                bestStreakAchievedOn: profile.bestStreakAchievedOn,
                lastActiveDay: profile.lastActiveDate.map { CivilDay(of: $0, in: calendar) }
            ),
            ledgerState: ledger.state(userId: userId)
        )
    }
    #endif
}
