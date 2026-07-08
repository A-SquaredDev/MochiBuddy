//
//  NotificationPrefsViewModel.swift
//  MochiBuddy
//
//  "Gentle nudges, never nags" — the chattiness dial and per-type toggles.
//  Every change persists immediately to the profile document.
//

import Foundation
import UserNotifications

final class NotificationPrefsViewModel: StateViewModel<
    NotificationPrefsBehavior.UIState,
    NotificationPrefsBehavior.ViewAction
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let permissionService: NotificationPermissionService

    // Domain source of truth — UIState is derived from this.
    private var prefs: NotificationPrefs = .standard
    private var bedtime: BedtimeWindow = .standard

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        permissionService: NotificationPermissionService
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.permissionService = permissionService
        var initial = NotificationPrefsBehavior.UIState()
        initial.levelOptions = [
            .init(id: NudgeLevel.rarely.rawValue, label: "Rarely"),
            .init(id: NudgeLevel.balanced.rawValue, label: "Balanced"),
            .init(id: NudgeLevel.chatty.rawValue, label: "Keep me on it"),
        ]
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: NotificationPrefsBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId, let profile = try? await profileRepository.fetchProfile(userId: userId) {
                prefs = profile.notificationPrefs
                bedtime = profile.bedtime
            }
            let status = await permissionService.authorizationStatus()
            rebuildState(systemDenied: status == .denied)

        case .selectLevel(let id):
            guard let level = NudgeLevel(rawValue: id) else { return }
            prefs.level = level
            await applyChange()

        case .setTaskReminders(let isOn):
            prefs.taskReminders = isOn
            await applyChange()

        case .setMorningRundown(let isOn):
            prefs.morningRundown = isOn
            await applyChange()

        case .setMoodDips(let isOn):
            prefs.moodDips = isOn
            await applyChange()

        case .setBedtimeSilence(let isOn):
            prefs.bedtimeSilence = isOn
            await applyChange()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func applyChange() async {
        rebuildState(systemDenied: uiState.systemDenied)
        guard let userId else { return }
        try? await profileRepository.saveNotificationPrefs(prefs, userId: userId)
    }

    private func rebuildState(systemDenied: Bool) {
        setUIState(
            uiState
                .updating(\.selectedLevelId, to: prefs.level.rawValue)
                .updating(\.taskReminders, to: prefs.taskReminders)
                .updating(\.morningRundown, to: prefs.morningRundown)
                .updating(\.moodDips, to: prefs.moodDips)
                .updating(\.bedtimeSilence, to: prefs.bedtimeSilence)
                .updating(\.bedtimeSilenceSub, to: "No pings \(Self.window(bedtime))")
                .updating(\.systemDenied, to: systemDenied)
        )
    }

    private static func window(_ bedtime: BedtimeWindow) -> String {
        "\(time(bedtime.startMinutes)) – \(time(bedtime.endMinutes))"
    }

    private static func time(_ minutes: Int) -> String {
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
