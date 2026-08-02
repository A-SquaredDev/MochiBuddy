//
//  NotificationPrefsViewModel.swift
//  MochiBuddy
//
//  "Gentle nudges, never nags" - the per-type notification toggles.
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
    private let relay: NotificationRelaying

    // Domain source of truth - UIState is derived from this.
    private var prefs: NotificationPrefs = .standard
    private var bedtime: BedtimeWindow = .standard
    private var petName = "Mochi"

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        permissionService: NotificationPermissionService,
        relay: NotificationRelaying
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.permissionService = permissionService
        self.relay = relay
        super.init(initialState: NotificationPrefsBehavior.UIState())
    }

    override func triggerAsync(_ action: NotificationPrefsBehavior.ViewAction) async {
        switch action {
        case .load:
            if let userId, let profile = try? await profileRepository.fetchProfile(userId: userId) {
                prefs = profile.notificationPrefs
                bedtime = profile.bedtime
                petName = profile.mochiName
            }
            let status = await permissionService.authorizationStatus()
            rebuildState(permissionIssue: Self.issue(for: status))

        case .enableFullNotifications:
            // Only reachable from the provisional banner: provisional has
            // not consumed the one-shot system dialog, so this shows the
            // real prompt. (From .denied the View opens Settings instead.)
            _ = await permissionService.requestAuthorization()
            let status = await permissionService.authorizationStatus()
            rebuildState(permissionIssue: Self.issue(for: status))
            relay.requestRelay(.prefsChange)

        case .setTaskReminders(let isOn):
            prefs.taskReminders = isOn
            await applyChange()

        case .setDefaultReminderTime(let date):
            prefs.defaultReminderMinutes = Self.minutes(from: date)
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

        case .setHideTaskNames(let isOn):
            prefs.hideTaskNames = isOn
            await applyChange()

        case .setWeeklyLetter(let isOn):
            prefs.weeklyLetter = isOn
            await applyChange()
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func applyChange() async {
        rebuildState(permissionIssue: uiState.permissionIssue)
        guard let userId else { return }
        try? await profileRepository.saveNotificationPrefs(prefs, userId: userId)
        relay.requestRelay(.prefsChange)
    }

    private static func issue(
        for status: UNAuthorizationStatus
    ) -> NotificationPrefsBehavior.PermissionIssue? {
        switch status {
        case .denied: .denied
        case .provisional: .provisional
        default: nil
        }
    }

    private func rebuildState(permissionIssue: NotificationPrefsBehavior.PermissionIssue?) {
        setUIState(
            uiState
                .updating(\.petName, to: petName)
                .updating(\.taskReminders, to: prefs.taskReminders)
                .updating(
                    \.defaultReminderTime,
                    to: Self.date(fromMinutes: prefs.effectiveDefaultReminderMinutes)
                )
                .updating(\.morningRundown, to: prefs.morningRundown)
                .updating(\.moodDips, to: prefs.moodDips)
                .updating(\.bedtimeSilence, to: prefs.bedtimeSilence)
                .updating(\.bedtimeSilenceSub, to: "No pings \(Self.window(bedtime))")
                .updating(\.hideTaskNames, to: prefs.hideTaskNames)
                .updating(\.weeklyLetter, to: prefs.weeklyLetter)
                .updating(\.permissionIssue, to: permissionIssue)
        )
    }

    private static func window(_ bedtime: BedtimeWindow) -> String {
        "\(time(bedtime.startMinutes)) – \(time(bedtime.endMinutes))"
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(hour: minutes / 60, minute: minutes % 60)
        ) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
    }

    private static func time(_ minutes: Int) -> String {
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
