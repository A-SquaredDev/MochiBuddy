//
//  SuggestionService.swift
//  MochiBuddy
//
//  The thin orchestrator over the pure suggestion engine (Personal
//  Layer, Feature 5). One editor open = one session: inputs are fetched
//  once (the existing observation fetch, no new query), distributions
//  re-scope purely over the cached inputs as the draft's list changes,
//  and the ledger + telemetry writes all funnel through here. The
//  downstream retention signal is computed lazily when an accepted
//  task/series is next edited - coarse buckets only, nothing leaves
//  the device.
//

import Foundation

@MainActor
final class SuggestionService {

    /// Everything an editor session evaluates against, frozen at open
    /// (except the list distribution, which re-scopes purely on demand).
    struct Session {
        let userId: String
        let inputs: ObservationEngine.Inputs
        let bedtime: BedtimeWindow
        let isLapsed: Bool
        /// Minted for unsaved tasks so a dismissal survives the save.
        let preallocatedTaskId: String?
    }

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let observationService: ObservationService
    private let membershipSession: MembershipSession
    private let ledger: SuggestionLedger
    private let telemetry: SuggestionTelemetry?
    private let calendar: Calendar

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        observationService: ObservationService,
        membershipSession: MembershipSession,
        ledger: SuggestionLedger,
        telemetry: SuggestionTelemetry? = nil,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.observationService = observationService
        self.membershipSession = membershipSession
        self.ledger = ledger
        self.telemetry = telemetry
        self.calendar = calendar
    }

    // MARK: - Session assembly

    func beginSession(editingTask: TaskItem?, now: Date = .now) async -> Session? {
        guard let userId = authRepository.currentAccount?.uid,
              let inputs = await observationService.engineInputs(now: now, calendar: calendar)
        else { return nil }
        let profile = try? await profileRepository.fetchProfile(userId: userId)
        let session = Session(
            userId: userId,
            inputs: inputs,
            bedtime: (profile?.bedtime ?? .standard).sanitized,
            isLapsed: membershipSession.isLapsed,
            preallocatedTaskId: editingTask == nil
                ? taskRepository.allocateTaskId(userId: userId)
                : nil
        )
        if let editingTask {
            reportPendingRetention(for: editingTask, session: session, now: now)
        }
        return session
    }

    /// The engine context for the draft's CURRENT scope targets - a pure
    /// re-scope over the session's cached inputs (the engine is pure, so
    /// no re-fetch accompanies a list change mid-session).
    func engineContext(
        session: Session, seriesIdentity: String?, listId: String?, now: Date = .now
    ) -> SuggestionEngine.Context {
        SuggestionEngine.Context(
            series: seriesIdentity.map {
                ObservationEngine.suggestionDistribution(scope: .series($0), inputs: session.inputs)
            },
            list: listId.map {
                ObservationEngine.suggestionDistribution(scope: .list($0), inputs: session.inputs)
            },
            global: ObservationEngine.suggestionDistribution(scope: .global, inputs: session.inputs),
            bedtime: session.bedtime,
            isLapsed: session.isLapsed,
            today: CivilDay(of: now, in: calendar).dateString,
            nowMinute: minuteOfDay(now)
        )
    }

    func minuteOfDay(_ instant: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Ledger reads/writes

    func dismissedMinute(_ trigger: SuggestionTrigger, id: String, userId: String) -> Int? {
        ledger.dismissedMinute(trigger, id: id, userId: userId)
    }

    func recordDismissed(
        _ trigger: SuggestionTrigger, id: String, displayedMinute: Int, userId: String
    ) {
        ledger.recordDismissed(trigger, id: id, displayedMinute: displayedMinute, userId: userId)
    }

    // MARK: - Telemetry

    /// The denominator - the caller (the editor session) guarantees at
    /// most one call per trigger per session where preconditions held.
    func recordEvaluated(_ evaluation: SuggestionEvaluation, userId: String) {
        telemetry?.log(.evaluated(
            trigger: evaluation.trigger,
            qualified: evaluation.proposal != nil,
            blockedReason: evaluation.blocked?.rawValue ?? "none"
        ))
    }

    func recordShown(_ proposal: SuggestionProposal, userId: String) {
        telemetry?.log(.shown(
            trigger: proposal.trigger,
            tier: proposal.tier,
            evidenceBucket: ObservationTelemetryBuckets.evidence(proposal.evidenceCount),
            recurring: proposal.isRecurring
        ))
    }

    /// Save-based terminal outcome. An acceptance also enters the ledger
    /// as retention's input.
    func recordOutcome(
        _ outcome: SuggestionOutcome,
        proposal: SuggestionProposal,
        taskId: String,
        seriesId: String?,
        userId: String,
        now: Date = .now
    ) {
        telemetry?.log(.outcome(trigger: proposal.trigger, tier: proposal.tier, outcome: outcome))
        if outcome == .accepted {
            ledger.recordAcceptance(SuggestionLedger.AcceptanceRecord(
                trigger: proposal.trigger.rawValue,
                tier: proposal.tier.rawValue,
                taskId: taskId,
                seriesId: seriesId,
                minute: proposal.displayedMinute,
                acceptedOn: CivilDay(of: now, in: calendar).dateString,
                retentionReported: false
            ), userId: userId)
        }
    }

    // MARK: - Downstream retention (coarse, device-computed)

    /// "Did it actually help": evaluated when the accepted task/series is
    /// next edited. Survival reads the task's current due time; the
    /// completion check scans the session's already-fetched records for a
    /// later completion near the accepted time. Coarse buckets only.
    private func reportPendingRetention(for task: TaskItem, session: Session, now: Date) {
        let pending = ledger.pendingAcceptances(
            taskId: task.id, seriesId: task.seriesId, userId: session.userId
        )
        guard !pending.isEmpty else { return }

        let scheduledMinute: Int? = task.hasTime ? task.dueAt.map(minuteOfDay) : nil
        for record in pending {
            guard let trigger = SuggestionTrigger(rawValue: record.trigger),
                  let tier = SuggestionScopeTier(rawValue: record.tier)
            else {
                ledger.markRetentionReported(record, userId: session.userId)
                continue
            }
            let survived = scheduledMinute == record.minute
            let identity = record.seriesId ?? record.taskId
            let completedNear = session.inputs.records.contains { stat in
                (stat.seriesId ?? stat.taskId) == identity
                    && stat.completedLocalDate > record.acceptedOn
                    && SuggestionEngine.circularDistance(stat.completedLocalMinute, record.minute) <= 90
            }
            let change = trigger == .reTime && !survived ? "reversed" : (survived ? "survived" : "changed")
            telemetry?.log(.retention(
                trigger: trigger, tier: tier,
                bucket: "\(change)-\(completedNear ? "completedNear" : "noCompletionNear")"
            ))
            ledger.markRetentionReported(record, userId: session.userId)
        }
    }

    /// Account deletion clears the UID's cadence outright.
    func clear(userId: String) {
        ledger.clear(userId: userId)
    }
}
