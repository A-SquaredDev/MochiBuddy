//
//  ObservationIntervalRecorder.swift
//  MochiBuddy
//
//  Maintains the synced vacation/lapse interval log (Personal Layer,
//  Feature 4). Transitions are recorded where they happen - vacation entry
//  (Vacation screen), every vacation end (re-entry service, which knows
//  the TRUE end even when the trip expired while the app was closed), and
//  membership status changes (AppContainer hook). `reconcile` runs at home
//  entry as the backstop for transitions this device never witnessed:
//  it stamps the log start once and realigns open intervals with the
//  profile's actual state, so a missed event degrades to a slightly-late
//  boundary, never a permanently wrong log.
//

import Foundation

@MainActor
final class ObservationIntervalRecorder {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository

    init(authRepository: AuthRepository, profileRepository: UserProfileRepository) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
    }

    // MARK: - Transition hooks

    /// Vacation entry (the Vacation screen's toggle).
    func vacationStarted(at start: Date = .now) async {
        await mutate { $0.appending(open: .vacation, at: start) }
    }

    /// Every vacation end routes through the re-entry service, which
    /// passes the effective end - the scheduled/capped instant when the
    /// trip expired while away, or "now" for a manual end.
    func vacationEnded(at end: Date) async {
        await mutate { $0.closing(.vacation, at: end) }
    }

    /// Entitlement snapshot changed (AppContainer's session hook). Opens
    /// or closes the lapse interval only on a real transition.
    func membershipChanged(isLapsed: Bool, at instant: Date = .now) async {
        await mutate { intervals in
            isLapsed
                ? intervals.appending(open: .lapse, at: instant)
                : intervals.closing(.lapse, at: instant)
        }
    }

    // MARK: - Home-entry backstop

    /// Stamp the log start once, then realign open intervals with the
    /// profile's live state (a vacation that ended by cap while the app
    /// was closed still flows through re-entry with its true end first;
    /// this only catches what no hook ever saw).
    func reconcile(isLapsed: Bool, now: Date = .now) async {
        guard let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId)
        else { return }

        if profile.observationLogSince == nil {
            try? await profileRepository.stampObservationLogSince(now, userId: userId)
        }

        var intervals = profile.observationIntervals
        if profile.vacationActive(at: now) {
            // Entered on another device: open from the recorded start.
            intervals = intervals.appending(
                open: .vacation, at: profile.vacationStartedAt ?? now
            )
        } else if let open = intervals.openInterval(.vacation) {
            // The end hook never ran (reinstall, another device): close at
            // the best boundary the schedule can attest, else now.
            let end = VacationSchedule.effectiveEnd(
                startedAt: open.start, resumeAt: profile.vacationResumeAt
            )
            intervals = intervals.closing(.vacation, at: min(end ?? now, now))
        }
        intervals = isLapsed
            ? intervals.appending(open: .lapse, at: now)
            : intervals.closing(.lapse, at: now)

        if intervals != profile.observationIntervals {
            try? await profileRepository.saveObservationIntervals(intervals, userId: userId)
        }
    }

    private func mutate(_ change: ([ObservationInterval]) -> [ObservationInterval]) async {
        guard let userId = authRepository.currentAccount?.uid,
              let profile = try? await profileRepository.fetchProfile(userId: userId)
        else { return }
        let updated = change(profile.observationIntervals)
        guard updated != profile.observationIntervals else { return }
        try? await profileRepository.saveObservationIntervals(updated, userId: userId)
    }
}
