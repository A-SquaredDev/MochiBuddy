//
//  NotificationOrchestrator.swift
//  MochiBuddy
//
//  The re-lay: snapshot the world, plan, diff, apply. Debounced against
//  mutation storms, idempotent, and scoped (the diff never touches a
//  promise that should live). Owns the small persisted scheduler state:
//  taper stretch, the shh valve, and copy rotation.
//
//  Everything interesting happens in the pure layers this composes -
//  MoodForecast, NotificationPlanner, NotificationPlanDiffer,
//  NotificationRequestBuilder - all separately tested. relayNow(_:now:)
//  is deterministic given its stores, so the composition is testable too.
//

import Foundation

enum RelayTrigger: String {
    case appForeground
    case taskChange
    case comfortChange
    case vacationChange
    case bedtimeChange
    case prefsChange
    case entitlementChange
    case notificationAction
    case timezoneChange
    /// A rename: mood pings + rundowns rewritten with the new name;
    /// promises untouched (they contain no name, by the locked rule).
    case petIdentityChange
    /// A letter composed, or its period turned non-dormant, or the
    /// weekly-letter toggle moved (Feature 3).
    case letterChange
}

@MainActor
final class NotificationOrchestrator {

    enum Constants {
        /// Planning horizon. Dormant users are exactly predictable, so one
        /// generous window serves everyone in v1. Remote-tunable.
        static var horizonDays = 7
        /// Mutation-storm debounce for requestRelay.
        static let debounce: Duration = .milliseconds(300)
        /// Remote-tunable, set once at launch.
        static var shhDuration: TimeInterval = 24 * 3600
    }

    private enum Key {
        static let taper = "mochi.notif.taper"
        static let shhUntil = "mochi.notif.shhUntil"
        static let deck = "mochi.notif.copyDeck"
    }

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let recurrenceRoller: RecurrenceRoller
    private let bufferStore: ComfortBufferStore
    private let membershipSession: MembershipSession
    private let scheduler: NotificationScheduling
    private let telemetry: NotificationTelemetry
    private let defaults: UserDefaults
    private let calendar: Calendar

    private var pendingRelay: Task<Void, Never>?

    /// Fired after every lay with the context it planned from - the
    /// widget mirror hangs here so the App Group snapshot and the pending
    /// queue always come from the same world.
    var onRelaid: ((RelayContext) -> Void)?

    /// Weekly letter (Feature 3): supplies the current period's identity
    /// and cutoff ONLY once the period is already non-dormant - wired by
    /// AppContainer to the letter service so the scheduling invariant
    /// lives with the marker's owner.
    var letterInputProvider: ((Date) async -> LetterNotificationInput?)?

    /// Anniversaries + memory callbacks (Feature 2): chooses the one
    /// Personal-Layer line per planned rundown and commits the cadence
    /// consequences - wired by AppContainer to MemoriesService. Keyed by
    /// the rundown's civil date string.
    var personalLayerProvider: ((PersonalLayerRequest) async -> [String: PersonalLayerContent])?

    /// Everything the Personal-Layer assignment needs from one relay.
    struct PersonalLayerRequest {
        let rundowns: [PlannedNotification]
        let snapshot: MoodSnapshot
        let taper: TaperState
        let completionTimes: [WeightedCompletion]
        let now: Date
    }

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        recurrenceRoller: RecurrenceRoller,
        bufferStore: ComfortBufferStore,
        membershipSession: MembershipSession,
        scheduler: NotificationScheduling,
        telemetry: NotificationTelemetry,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.recurrenceRoller = recurrenceRoller
        self.bufferStore = bufferStore
        self.membershipSession = membershipSession
        self.scheduler = scheduler
        self.telemetry = telemetry
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Entry points

    /// Debounced: rapid mutations (bulk edits, toggle sprees) coalesce
    /// into one lay a beat after the last change.
    func requestRelay(_ trigger: RelayTrigger) {
        pendingRelay?.cancel()
        pendingRelay = Task { [weak self] in
            try? await Task.sleep(for: Constants.debounce)
            guard !Task.isCancelled else { return }
            await self?.relayNow(trigger)
        }
    }

    /// The world as the planner sees it - also served to the DEBUG
    /// inspector so its view can never drift from the real inputs.
    struct RelayContext {
        let userId: String
        let snapshot: MoodSnapshot
        let prefs: NotificationPrefs
        let bedtime: BedtimeWindow
        let lapsed: Bool
        /// The pet's name at plan time - dresses mood pings and rundowns,
        /// and rides into the widget mirror so both stay in step.
        let petName: String
        /// The weekly-letter invitation input, when its period qualifies.
        var letter: LetterNotificationInput? = nil
    }

    func makeContext(now: Date = .now) async -> RelayContext? {
        guard let userId = authRepository.currentAccount?.uid else { return nil }
        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let lapsed = membershipSession.isLapsed
        let onVacation = profile?.vacationActive(at: now) ?? false

        var tasks = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        tasks = await recurrenceRoller.rollForward(
            tasks, frozen: onVacation || lapsed, userId: userId, now: now, calendar: calendar
        )
        let dayAgo = now.addingTimeInterval(-MoodForecast.momentumWindow)
        let completions = ((try? await taskRepository.completedTasks(since: dayAgo, userId: userId)) ?? [])
            .compactMap { task in
                task.completedAt.map {
                    WeightedCompletion(
                        date: $0,
                        weight: EffortConstants.weight(estimatedMinutes: task.estimatedMinutes)
                    )
                }
            }

        return RelayContext(
            userId: userId,
            snapshot: MoodSnapshot(
                tasks: tasks,
                completionTimes: completions,
                boosts: bufferStore.activeBoosts(now: now),
                vacationMode: profile?.vacationMode ?? false,
                vacationResumeAt: profile?.vacationResumeAt,
                vacationStartedAt: profile?.vacationStartedAt,
                entitlementExpiry: entitlementExpiry(),
                capturedAt: now
            ),
            prefs: profile?.notificationPrefs ?? .standard,
            bedtime: profile?.bedtime ?? .standard,
            lapsed: lapsed,
            petName: profile?.mochiName ?? PetNameSanitizer.defaultName,
            letter: await letterInputProvider?(now)
        )
    }

    /// The persisted taper stretch - read-only view for the inspector.
    func currentTaperState() -> TaperState {
        loadTaper()
    }

    func relayNow(_ trigger: RelayTrigger, now: Date = .now) async {
        guard let context = await makeContext(now: now) else { return }
        let snapshot = context.snapshot
        let tasks = snapshot.tasks
        let completions = snapshot.completionTimes
        let prefs = context.prefs

        // Fold this observation into the taper stretch before planning.
        let band = MoodForecast.band(at: now, snapshot: snapshot, calendar: calendar)
        let taper = TaperTracker.update(loadTaper(), band: band, now: now, calendar: calendar)
        saveTaper(taper)
        let floorDays = taper.consecutiveFloorDays(before: now, calendar: calendar)

        let horizon = calendar.date(byAdding: .day, value: Constants.horizonDays, to: now)
            ?? now.addingTimeInterval(TimeInterval(Constants.horizonDays) * 24 * 3600)
        let plan = NotificationPlanner.plan(
            NotificationPlanInput(
                snapshot: snapshot,
                bedtime: context.bedtime,
                prefs: prefs,
                lapsed: context.lapsed,
                shhUntil: shhUntil(now: now),
                consecutiveFloorDays: floorDays,
                letter: context.letter,
                horizon: horizon
            ),
            calendar: calendar
        )

        let diff = NotificationPlanDiffer.diff(desired: plan, pendingIds: await scheduler.pendingIds())
        scheduler.removePending(ids: diff.removeIds)

        // The one Personal-Layer line per rundown morning (Feature 2's
        // canonical priority), assigned for the whole horizon in one
        // deterministic pass so cadence threads across the laid days.
        var personalByDate: [String: PersonalLayerContent]?
        if let personalLayerProvider {
            personalByDate = await personalLayerProvider(PersonalLayerRequest(
                rundowns: plan.filter { $0.kind == .rundown },
                snapshot: snapshot,
                taper: taper,
                completionTimes: completions,
                now: now
            ))
        }

        var deck = loadDeck()
        let tasksById = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Copy shifts acute → chronic on day 3 of the stretch, with the
        // same counter the cadence taper reads.
        let floorPhase: NotificationCopy.FloorPhase = floorDays >= 2 ? .chronic : .acute
        for planned in diff.schedule {
            let slot: PersonalLayerSlot
            if planned.kind == .rundown, let personalByDate {
                let date = CivilDay(of: planned.fireAt, in: calendar).dateString
                slot = personalByDate[date].map { .line($0) } ?? PersonalLayerSlot.none
            } else {
                slot = .unavailable
            }
            let request = NotificationRequestBuilder.request(
                for: planned,
                tasksById: tasksById,
                allTasks: tasks,
                completionTimes: completions,
                floorPhase: floorPhase,
                hideTaskNames: prefs.hideTaskNames,
                petName: context.petName,
                personal: slot,
                deck: &deck,
                calendar: calendar
            )
            await scheduler.schedule(request)
        }
        saveDeck(deck)

        telemetry.log(.relaid(
            trigger: trigger.rawValue,
            scheduled: diff.schedule.count,
            removed: diff.removeIds.count,
            band: band
        ))
        onRelaid?(context)
    }

    // MARK: - The shh valve

    /// "Mochi, shh" - 24 hours of mood-ping silence, never touching a
    /// promise, never resetting the taper.
    func activateShh(now: Date = .now) async {
        defaults.set(now.addingTimeInterval(Constants.shhDuration), forKey: Key.shhUntil)
        await relayNow(.notificationAction, now: now)
    }

    func shhUntil(now: Date = .now) -> Date? {
        guard let until = defaults.object(forKey: Key.shhUntil) as? Date, until > now else {
            return nil
        }
        return until
    }

    // MARK: - Persisted state

    private func entitlementExpiry() -> Date? {
        switch membershipSession.status {
        case .trial(let endsAt): endsAt
        case .active(_, let renewsAt): renewsAt
        case .billingGrace(_, let renewsAt): renewsAt
        case .lapsed, .notSubscribed: nil // the lapsed flag already gates
        }
    }

    private func loadTaper() -> TaperState {
        guard let data = defaults.data(forKey: Key.taper),
              let state = try? JSONDecoder().decode(TaperState.self, from: data)
        else { return TaperState() }
        return state
    }

    private func saveTaper(_ state: TaperState) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Key.taper)
    }

    private func loadDeck() -> CopyDeck {
        guard let data = defaults.data(forKey: Key.deck),
              let deck = try? JSONDecoder().decode(CopyDeck.self, from: data)
        else { return CopyDeck() }
        return deck
    }

    private func saveDeck(_ deck: CopyDeck) {
        defaults.set(try? JSONEncoder().encode(deck), forKey: Key.deck)
    }
}
