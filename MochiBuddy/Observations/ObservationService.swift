//
//  ObservationService.swift
//  MochiBuddy
//
//  The thin orchestrator over the pure engine (Personal Layer, Feature 4):
//  gathers inputs (completion records over the fixed fetch horizon, the
//  synced interval log, surviving list ids), runs the engine, and logs the
//  observation_evaluated denominator - at most once per type per user-day,
//  throttled by the ledger. Surfaces (letter beats, rundown lines, the
//  Journal card) consume the qualified set through here; the DEBUG
//  inspector reads the full candidate story.
//
//  Lapsed: composing surfaces don't run, so the engine simply isn't
//  consulted - the Journal card shows the last qualified set, frozen.
//

import Foundation

@MainActor
final class ObservationService {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let ledger: ObservationLedger
    private let telemetry: ObservationTelemetry?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        ledger: ObservationLedger,
        telemetry: ObservationTelemetry? = nil
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.ledger = ledger
        self.telemetry = telemetry
    }

    var currentUserId: String? {
        authRepository.currentAccount?.uid
    }

    /// The memoized expensive half of the inputs: the 132-day completion
    /// scan and the list-id set, keyed by (userId, civil day). The profile
    /// half (intervals, logSince) is refetched every call - it comes from
    /// the write-through profile cache, so it is free and always current.
    /// Invalidated by every task mutation (CachingTaskRepository.onMutation,
    /// wired in AppContainer) and by the day key rolling over. A list
    /// deleted mid-day can linger in the set until then; surfaces degrade
    /// gracefully (a list-return line without a surviving name renders nil,
    /// pinned by test).
    private var cachedFetch: (
        userId: String, day: String,
        records: [CompletedTaskStat], knownListIds: Set<String>
    )?

    /// Wired to the task cache's mutation hook - pre-mutation history must
    /// never satisfy a post-mutation read.
    func invalidateInputs() {
        cachedFetch = nil
    }

    /// The full engine evaluation at an instant. `now`/`calendar` are
    /// explicit so the inspector's time travel and tests replay history
    /// without touching a clock.
    func snapshot(
        now: Date = .now, calendar: Calendar = .current
    ) async -> ObservationEngine.Snapshot? {
        guard let userId = currentUserId,
              let inputs = await inputs(userId: userId, now: now, calendar: calendar)
        else { return nil }
        let snapshot = ObservationEngine.evaluate(inputs)
        logEvaluations(snapshot, now: now, calendar: calendar, userId: userId)
        return snapshot
    }

    /// Feature 5's distribution contract, provenance included.
    func timeOfDayDistribution(
        listId: String?, now: Date = .now, calendar: Calendar = .current
    ) async -> DistributionResult? {
        guard let userId = currentUserId,
              let inputs = await inputs(userId: userId, now: now, calendar: calendar)
        else { return nil }
        return ObservationEngine.timeOfDayDistribution(listId: listId, inputs: inputs)
    }

    /// Raw per-scope distribution for suggested times (Feature 5) - no
    /// fallback logic; scope precedence belongs to the suggestion engine.
    func suggestionDistribution(
        scope: ObservationEngine.SuggestionScope, now: Date = .now, calendar: Calendar = .current
    ) async -> DistributionResult? {
        guard let userId = currentUserId,
              let inputs = await inputs(userId: userId, now: now, calendar: calendar)
        else { return nil }
        return ObservationEngine.suggestionDistribution(scope: scope, inputs: inputs)
    }

    /// Marks an observation surfaced and returns its copy line (nil when
    /// the pool can't render, e.g. a list-return whose list name is gone).
    func surfaced(
        _ observation: QualifiedObservation,
        surface: ObservationLedger.Surface,
        petName: String,
        listName: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard let userId = currentUserId else { return nil }
        let day = CivilDay(of: now, in: calendar).dateString
        ledger.recordSurfaced(observation, surface: surface, on: day, userId: userId)
        telemetry?.log(.shown(
            kind: observation.kind,
            surface: surface.rawValue,
            confidenceBucket: "qualified"
        ))
        return ledger.nextLine(
            for: observation.conclusion, petName: petName, listName: listName, userId: userId
        )
    }

    // MARK: - Inputs

    /// The raw engine inputs - the DEBUG inspector fetches once and then
    /// re-evaluates synchronously as its time-travel slider moves (the
    /// engine is pure, so shifting `now` on cached inputs is sound).
    func engineInputs(
        now: Date = .now, calendar: Calendar = .current
    ) async -> ObservationEngine.Inputs? {
        guard let userId = currentUserId else { return nil }
        return await inputs(userId: userId, now: now, calendar: calendar)
    }

    private func inputs(
        userId: String, now: Date, calendar: Calendar
    ) async -> ObservationEngine.Inputs? {
        guard let profile = try? await profileRepository.fetchProfile(userId: userId) else {
            return nil
        }
        let day = CivilDay(of: now, in: calendar).dateString
        if let cached = cachedFetch, cached.userId == userId, cached.day == day {
            FirestoreReadLog.recordCacheHit(Self.self)
            return ObservationEngine.Inputs(
                records: cached.records,
                intervals: profile.observationIntervals,
                logSince: profile.observationLogSince,
                knownListIds: cached.knownListIds,
                calendar: calendar,
                now: now
            )
        }
        // The fixed fetch horizon: replay depth + the window each daily
        // snapshot looks back over (part of the algorithm's definition).
        let horizonDays = ObservationConstants.replayDays + ObservationConstants.windowDays
        let since = now.addingTimeInterval(-TimeInterval(horizonDays) * 86_400)
        let records = (try? await taskRepository.completedTaskStats(since: since, userId: userId)) ?? []
        let lists = (try? await listRepository.fetchLists(userId: userId)) ?? []
        let listIds = Set(lists.map(\.id))
        cachedFetch = (userId: userId, day: day, records: records, knownListIds: listIds)
        return ObservationEngine.Inputs(
            records: records,
            intervals: profile.observationIntervals,
            logSince: profile.observationLogSince,
            knownListIds: listIds,
            calendar: calendar,
            now: now
        )
    }

    // MARK: - Telemetry

    private func logEvaluations(
        _ snapshot: ObservationEngine.Snapshot, now: Date, calendar: Calendar, userId: String
    ) {
        guard let telemetry else { return }
        let day = CivilDay(of: now, in: calendar).dateString
        let qualifiedKinds = Set(snapshot.qualified.map(\.kind))
        for candidate in snapshot.candidates {
            guard ledger.shouldLogEvaluation(kind: candidate.kind, day: day, userId: userId) else {
                continue
            }
            telemetry.log(.evaluated(
                kind: candidate.kind,
                qualified: qualifiedKinds.contains(candidate.kind),
                evidenceBucket: ObservationTelemetryBuckets.evidence(candidate.evidenceCount),
                marginBucket: ObservationTelemetryBuckets.margin(topShare: candidate.topShare)
            ))
        }
    }
}
