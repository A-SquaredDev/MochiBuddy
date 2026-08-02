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
    /// Apple Reminders changed outside the app (EKEventStoreChanged).
    case remindersChange
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
        // Legacy device-scoped names. State under them predates per-user
        // scoping and is folded into the signed-in user's keys on first
        // read, so an account switch can never inherit another user's
        // taper stretch, shh valve, or copy rotation.
        static let legacyTaper = "mochi.notif.taper"
        static let legacyShhUntil = "mochi.notif.shhUntil"
        static let legacyDeck = "mochi.notif.copyDeck"

        static func taper(_ userId: String) -> String { "\(legacyTaper).\(userId)" }
        static func shhUntil(_ userId: String) -> String { "\(legacyShhUntil).\(userId)" }
        static func deck(_ userId: String) -> String { "\(legacyDeck).\(userId)" }
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

    /// The billing-notice audit trail: freshly scheduled trial notices
    /// are recorded, fired ones get delivery confirmed - wired by
    /// AppContainer to the Firestore recorder.
    var billingNoticeRecorder: BillingNoticeRecording?

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
        /// The upcoming trial-to-paid conversion, only while auto-renew
        /// is on - a cancelled trial plans no billing notices.
        var trialCharge: TrialChargeInput? = nil
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
            letter: await letterInputProvider?(now),
            trialCharge: trialCharge()
        )
    }

    private func trialCharge() -> TrialChargeInput? {
        guard case .trial(let endsAt, true) = membershipSession.status else { return nil }
        return TrialChargeInput(endsAt: endsAt)
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
                trialCharge: context.trialCharge,
                horizon: horizon
            ),
            calendar: calendar
        )

        let pendingBefore = await scheduler.pendingIds()
        let diff = NotificationPlanDiffer.diff(desired: plan, pendingIds: pendingBefore)
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

        // The billing-notice audit trail. Recording keys off "newly
        // pending": every re-lay re-schedules the same ids in place, but
        // only a notice iOS didn't already hold is a fresh scheduling
        // fact. The delivered sweep runs regardless of current status -
        // a notice fired during a trial is still confirmable after the
        // trial converts.
        if let recorder = billingNoticeRecorder {
            if let trial = context.trialCharge {
                let alreadyPending = Set(pendingBefore)
                for planned in diff.schedule
                where planned.kind == .trialEnding && !alreadyPending.contains(planned.id) {
                    await recorder.recordScheduled(planned, trialEndsAt: trial.endsAt)
                }
            }
            let fired = await scheduler.deliveredIds()
                .filter { $0.hasPrefix(NotificationID.trialPrefix) }
            if !fired.isEmpty {
                recorder.confirmDelivered(ids: fired)
            }
        }

        telemetry.log(.relaid(
            trigger: trigger.rawValue,
            scheduled: diff.schedule.count,
            removed: diff.removeIds.count,
            band: band
        ))
        onRelaid?(context)
    }

    // MARK: - Identity exit

    /// Sign-out or account deletion: cancel any queued relay, remove every
    /// pending notification this app owns, and drop the exiting user's
    /// persisted taper/shh/copy state. Without this the old identity's
    /// task-titled promises and the repeating backstop keep firing forever,
    /// and the next account inherits a taper stretch it never earned. The
    /// caller passes the exiting uid explicitly because sign-out may
    /// already have cleared currentAccount by the time this runs.
    func clearForIdentityExit(userId: String?) async {
        pendingRelay?.cancel()
        pendingRelay = nil
        let ours = await scheduler.pendingIds().filter(NotificationPlanDiffer.isOurs)
        scheduler.removePending(ids: ours)
        if let userId {
            defaults.removeObject(forKey: Key.taper(userId))
            defaults.removeObject(forKey: Key.shhUntil(userId))
            defaults.removeObject(forKey: Key.deck(userId))
        }
        defaults.removeObject(forKey: Key.legacyTaper)
        defaults.removeObject(forKey: Key.legacyShhUntil)
        defaults.removeObject(forKey: Key.legacyDeck)
    }

    // MARK: - The shh valve

    /// "Mochi, shh" - 24 hours of mood-ping silence, never touching a
    /// promise, never resetting the taper.
    func activateShh(now: Date = .now) async {
        guard let key = stateKey(Key.shhUntil, legacy: Key.legacyShhUntil) else { return }
        defaults.set(now.addingTimeInterval(Constants.shhDuration), forKey: key)
        await relayNow(.notificationAction, now: now)
    }

    func shhUntil(now: Date = .now) -> Date? {
        guard let key = stateKey(Key.shhUntil, legacy: Key.legacyShhUntil),
              let until = defaults.object(forKey: key) as? Date, until > now else {
            return nil
        }
        return until
    }

    // MARK: - Persisted state

    /// The signed-in user's key for one piece of scheduler state, folding
    /// any legacy device-scoped value into it on the way. Nil when signed
    /// out - state neither loads nor saves without an identity to own it.
    private func stateKey(_ namespaced: (String) -> String, legacy: String) -> String? {
        guard let userId = authRepository.currentAccount?.uid else { return nil }
        let key = namespaced(userId)
        if let carried = defaults.object(forKey: legacy) {
            if defaults.object(forKey: key) == nil {
                defaults.set(carried, forKey: key)
            }
            defaults.removeObject(forKey: legacy)
        }
        return key
    }

    private func entitlementExpiry() -> Date? {
        // When auto-renew is on, the known end date is a renewal boundary,
        // not an entitlement cliff - capping there would starve the horizon
        // (sandbox yearly subs renew hourly; trials cap from day 1). Only a
        // real cancellation (willRenew == false) caps the plan.
        switch membershipSession.status {
        case .trial(let endsAt, let willRenew): willRenew ? nil : endsAt
        case .active(_, let renewsAt, let willRenew): willRenew ? nil : renewsAt
        case .billingGrace(_, let renewsAt, let willRenew): willRenew ? nil : renewsAt
        case .lapsed, .notSubscribed: nil // the lapsed flag already gates
        }
    }

    private func loadTaper() -> TaperState {
        guard let key = stateKey(Key.taper, legacy: Key.legacyTaper),
              let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(TaperState.self, from: data)
        else { return TaperState() }
        return state
    }

    private func saveTaper(_ state: TaperState) {
        guard let key = stateKey(Key.taper, legacy: Key.legacyTaper) else { return }
        defaults.set(try? JSONEncoder().encode(state), forKey: key)
    }

    private func loadDeck() -> CopyDeck {
        guard let key = stateKey(Key.deck, legacy: Key.legacyDeck),
              let data = defaults.data(forKey: key),
              let deck = try? JSONDecoder().decode(CopyDeck.self, from: data)
        else { return CopyDeck() }
        return deck
    }

    private func saveDeck(_ deck: CopyDeck) {
        guard let key = stateKey(Key.deck, legacy: Key.legacyDeck) else { return }
        defaults.set(try? JSONEncoder().encode(deck), forKey: key)
    }
}
