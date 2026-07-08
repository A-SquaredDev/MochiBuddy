//
//  YouViewModel.swift
//  MochiBuddy
//
//  The "You" tab — preferences, Mochi's care, account & legal. Rebuilds
//  from the profile document on every refresh (returning from sub-screens
//  must reflect their edits).
//

import Foundation

final class YouViewModel: ObservableStateViewModel<
    YouBehavior.UIState,
    YouBehavior.ViewAction,
    YouBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let listRepository: ListRepository
    private let membershipStore: MembershipStore
    private let themeStore: ThemeStore

    // Domain source of truth — UIState is derived from this.
    private var profile: UserProfile?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        listRepository: ListRepository,
        membershipStore: MembershipStore,
        themeStore: ThemeStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.listRepository = listRepository
        self.membershipStore = membershipStore
        self.themeStore = themeStore

        var initial = YouBehavior.UIState()
        initial.flavors = MochiTheme.all.map {
            YouBehavior.FlavorSwatch(id: $0.id, color: $0.primary)
        }
        initial.selectedFlavorId = themeStore.current.id
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        initial.appVersion = "Mochi \(version ?? "1.0") · Rated 4+ · Made with care 🍡"
        super.init(initialState: initial)
    }

    override func triggerAsync(_ action: YouBehavior.ViewAction) async {
        switch action {
        case .refresh:
            await refresh()

        case .selectFlavor(let id):
            themeStore.apply(themeId: id)
            state.selectedFlavorId = id
            if let userId {
                try? await profileRepository.saveThemeId(id, userId: userId)
            }

        case .setMorningRundown(let isOn):
            profile?.notificationPrefs.morningRundown = isOn
            state.morningRundown = isOn
            if let userId, let prefs = profile?.notificationPrefs {
                try? await profileRepository.saveNotificationPrefs(prefs, userId: userId)
            }

        case .setSoundEnabled(let isOn):
            profile?.soundEnabled = isOn
            state.soundEnabled = isOn
            if let userId {
                try? await profileRepository.saveSoundEnabled(isOn, userId: userId)
            }

        case .restoreTapped:
            await restorePurchases()

        case .dismissRestoreMessage:
            state.restoreMessage = nil

        case .signOutTapped:
            state.showSignOutConfirm = true

        case .cancelSignOut:
            state.showSignOutConfirm = false

        case .confirmSignOut:
            state.showSignOutConfirm = false
            do {
                try authRepository.signOut()
                setNavigationEvent(.signedOut)
            } catch {
                state.restoreMessage = "Couldn't sign out. \(error.localizedDescription)"
            }

        case .bedtimeTapped: setNavigationEvent(.editBedtime)
        case .statsTapped: setNavigationEvent(.showStats)
        case .notificationsTapped: setNavigationEvent(.showNotifications)
        case .remindersTapped: setNavigationEvent(.showReminders)
        case .vacationTapped: setNavigationEvent(.showVacation)
        case .manageListsTapped: setNavigationEvent(.showManageLists)
        case .deleteAccountTapped: setNavigationEvent(.startDeleteFlow)
        }
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    private func refresh() async {
        let account = authRepository.currentAccount

        var next = uiState
        next.selectedFlavorId = themeStore.current.id

        if let account, !account.isAnonymous {
            next.displayName = account.displayName ?? "Mochi friend"
            next.identitySub = account.email ?? "Signed in"
        } else {
            next.displayName = "Mochi friend"
            next.identitySub = "Guest account"
        }
        next.avatarLetter = String(next.displayName.prefix(1)).uppercased()

        if let userId, let fetched = try? await profileRepository.fetchProfile(userId: userId) {
            profile = fetched
            next.coins = fetched.coins
            next.bedtimeText = Self.bedtimeText(fetched.bedtime)
            next.morningRundown = fetched.notificationPrefs.morningRundown
            next.soundEnabled = fetched.soundEnabled
            next.notificationsSub = "Gentle nudges · \(Self.levelText(fetched.notificationPrefs.level))"
            next.remindersSub = fetched.importedReminderListIds.isEmpty
                ? "Bring your Reminders in"
                : "\(fetched.importedReminderListIds.count) list\(fetched.importedReminderListIds.count == 1 ? "" : "s") syncing"
            next.vacationSub = fetched.vacationMode
                ? "On — nudges paused"
                : "Pause all nudges while you rest"
        } else {
            next.bedtimeText = Self.bedtimeText(.standard)
            next.notificationsSub = "Gentle nudges · balanced"
            next.remindersSub = "Bring your Reminders in"
            next.vacationSub = "Pause all nudges while you rest"
        }

        if let userId {
            let listCount = (try? await listRepository.fetchLists(userId: userId).count) ?? 0
            next.listsSub = "\(listCount) list\(listCount == 1 ? "" : "s")"
        }

        let status = await membershipStore.currentStatus()
        (next.isMember, next.subscriptionSub) = await membershipLine(for: status)
        if next.isMember, let email = account?.email {
            next.identitySub = "\(email) · Mochi+ member"
        }

        setUIState(next)
    }

    private func restorePurchases() async {
        state.isRestoring = true
        defer { state.isRestoring = false }

        guard let purchase = await membershipStore.restorablePurchase() else {
            state.restoreMessage = "Nothing to restore — this Apple ID has no active Mochi+ purchase."
            return
        }
        do {
            try await membershipStore.restore(purchase)
            Haptics.success()
            state.restoreMessage = "Welcome back — your membership is restored! 🎉"
            await refresh()
        } catch {
            state.restoreMessage = "Couldn't restore purchases. Please try again."
        }
    }

    private func membershipLine(for status: MembershipStatus) async -> (isMember: Bool, line: String) {
        switch status {
        case .active(let plan, let renewsAt):
            let option = await membershipStore.planOptions().first { $0.plan == plan }
            let priceText = option.map {
                "\($0.localizedPrice)/\(plan == .yearly ? "yr" : "mo")"
            } ?? (plan == .yearly ? "Yearly" : "Monthly")
            var line = "Mochi+ · \(priceText)"
            if let renewsAt {
                line += " · renews \(Self.dateText(renewsAt))"
            }
            return (true, line)
        case .trial(let endsAt):
            return (true, "Mochi+ · free trial ends \(Self.dateText(endsAt))")
        case .lapsed:
            return (false, "Lapsed — renew to keep Mochi thriving")
        case .notSubscribed:
            return (false, "Not subscribed yet")
        }
    }

    // MARK: - Formatting

    private static func levelText(_ level: NudgeLevel) -> String {
        switch level {
        case .rarely: "rarely"
        case .balanced: "balanced"
        case .chatty: "keep me on it"
        }
    }

    private static func bedtimeText(_ window: BedtimeWindow) -> String {
        "\(timeText(minutes: window.startMinutes)) – \(timeText(minutes: window.endMinutes))"
    }

    private static func timeText(minutes: Int) -> String {
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
