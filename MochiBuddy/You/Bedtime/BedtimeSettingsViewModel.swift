//
//  BedtimeSettingsViewModel.swift
//  MochiBuddy
//
//  Settings twin of the onboarding bedtime step — loads the saved window
//  and persists every change immediately (no explicit save button).
//

import Foundation

final class BedtimeSettingsViewModel: StateViewModel<
    BedtimeSettingsBehavior.UIState,
    BedtimeSettingsBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository

    // Domain source of truth — wall-clock minutes, not instants.
    private var window: BedtimeWindow = .standard

    init(authRepository: AuthRepository, profileRepository: UserProfileRepository) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        super.init(initialState: BedtimeSettingsBehavior.UIState())
    }

    override func triggerAsync(_ action: BedtimeSettingsBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId, let profile = try? await profileRepository.fetchProfile(userId: userId) {
                window = profile.bedtime
            }
            rebuildState(editing: .none)

        case .bedtimeTapped:
            rebuildState(editing: uiState.editing == .bedtime ? .none : .bedtime)

        case .wakeTapped:
            rebuildState(editing: uiState.editing == .wake ? .none : .wake)

        case .bedtimeChanged(let date):
            window.startMinutes = Self.minutes(from: date)
            rebuildState(editing: uiState.editing)
            await persist()

        case .wakeChanged(let date):
            window.endMinutes = Self.minutes(from: date)
            rebuildState(editing: uiState.editing)
            await persist()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func persist() async {
        guard let userId else { return }
        try? await profileRepository.saveBedtime(window, userId: userId)
    }

    private func rebuildState(editing: BedtimeSettingsBehavior.EditTarget) {
        setUIState(
            uiState
                .updating(\.bedtimeText, to: Self.format(minutes: window.startMinutes))
                .updating(\.wakeText, to: Self.format(minutes: window.endMinutes))
                .updating(\.bedtimeDate, to: Self.date(from: window.startMinutes))
                .updating(\.wakeDate, to: Self.date(from: window.endMinutes))
                .updating(\.editing, to: editing)
        )
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(from minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    private static func format(minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date(from: minutes))
    }
}
