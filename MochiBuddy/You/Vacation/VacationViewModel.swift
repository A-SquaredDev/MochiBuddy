//
//  VacationViewModel.swift
//  MochiBuddy
//
//  Vacation mode — pause nudges and stress accrual entirely. Optional
//  auto-resume date; otherwise on until turned off. Persists immediately.
//

import Foundation

final class VacationViewModel: StateViewModel<
    VacationBehavior.UIState,
    VacationBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository

    // Domain source of truth.
    private var isOn = false
    private var resumeAt: Date?

    init(authRepository: AuthRepository, profileRepository: UserProfileRepository) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        super.init(initialState: VacationBehavior.UIState())
    }

    override func triggerAsync(_ action: VacationBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId, let profile = try? await profileRepository.fetchProfile(userId: userId) {
                isOn = profile.vacationMode
                resumeAt = profile.vacationResumeAt
            }
            rebuildState()

        case .setVacation(let on):
            isOn = on
            if !on {
                resumeAt = nil
            }
            rebuildState()
            await persist()

        case .setAutoResume(let on):
            resumeAt = on ? Self.tomorrow : nil
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
            await persist()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func persist() async {
        guard let userId else { return }
        try? await profileRepository.saveVacation(mode: isOn, resumeAt: resumeAt, userId: userId)
    }

    private func rebuildState() {
        setUIState(
            uiState
                .updating(\.isOn, to: isOn)
                .updating(\.toggleSub, to: toggleSub)
                .updating(\.autoResume, to: resumeAt != nil)
                .updating(\.resumeDate, to: resumeAt ?? Self.tomorrow)
                .updating(\.minimumResumeDate, to: Self.tomorrow)
        )
    }

    private var toggleSub: String {
        guard isOn else { return "Off — nudges as usual" }
        guard let resumeAt else { return "On until you turn it off" }
        return "On until \(resumeAt.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private static var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
}
