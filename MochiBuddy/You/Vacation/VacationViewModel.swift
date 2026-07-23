//
//  VacationViewModel.swift
//  MochiBuddy
//
//  Vacation mode - pause nudges and stress accrual entirely. Optional
//  auto-resume date; otherwise on until turned off. Persists immediately.
//

import Foundation

final class VacationViewModel: StateViewModel<
    VacationBehavior.UIState,
    VacationBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let relay: NotificationRelaying
    private let reentryService: VacationReentryService

    // Domain source of truth.
    private var isOn = false
    private var resumeAt: Date?
    private var startedAt: Date?
    private var petName = "Mochi"

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        relay: NotificationRelaying,
        reentryService: VacationReentryService
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.relay = relay
        self.reentryService = reentryService
        super.init(initialState: VacationBehavior.UIState())
    }

    override func triggerAsync(_ action: VacationBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId, let profile = try? await profileRepository.fetchProfile(userId: userId) {
                isOn = profile.vacationMode
                resumeAt = profile.vacationResumeAt
                startedAt = profile.vacationStartedAt
                petName = profile.mochiName
            }
            rebuildState()

        case .setVacation(let on):
            if on, !isOn {
                // Entry: record when the trip began - it drives the
                // open-ended cap, the check-in, and the re-entry bucket.
                startedAt = .now
            }
            isOn = on
            if !on {
                resumeAt = nil
            }
            rebuildState()
            if on {
                await persist()
            } else {
                await endThroughReentry()
            }

        case .setAutoResume(let on):
            resumeAt = on ? Self.defaultEnd : nil
            rebuildState()
            await persist()

        case .resumeDateChanged(let date):
            resumeAt = date
            rebuildState()
            await persist()

        case .turnOffTapped:
            isOn = false
            resumeAt = nil
            Haptics.success()
            rebuildState()
            await endThroughReentry()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func persist() async {
        guard let userId else { return }
        try? await profileRepository.saveVacation(
            mode: isOn, resumeAt: resumeAt, startedAt: isOn ? startedAt : nil, userId: userId
        )
        // Entering clears the queue (truly silent); leaving re-lays it.
        relay.requestRelay(.vacationChange)
    }

    /// Every manual end routes through re-entry: bucket, grace, streak.
    private func endThroughReentry() async {
        guard let userId else { return }
        startedAt = nil
        await reentryService.endNow(userId: userId)
    }

    private func rebuildState() {
        setUIState(
            uiState
                .updating(\.petName, to: petName)
                .updating(\.isOn, to: isOn)
                .updating(\.toggleSub, to: toggleSub)
                .updating(\.autoResume, to: resumeAt != nil)
                .updating(\.resumeDate, to: resumeAt ?? Self.defaultEnd)
                .updating(\.minimumResumeDate, to: Self.tomorrow)
        )
    }

    /// The date picker's default trip length (design doc: 7 days out).
    private static var defaultEnd: Date {
        Calendar.current.date(
            byAdding: .day, value: VacationConstants.defaultDays,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
    }

    private var toggleSub: String {
        guard isOn else { return "Off · nudges as usual" }
        guard let resumeAt else { return "On until you turn it off" }
        return "On until \(resumeAt.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private static var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
}
