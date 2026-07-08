//
//  OnboardingStore.swift
//  MochiBuddy
//
//  Scoped shared store for the onboarding flow (created by the Router,
//  injected into the flow's ViewModels, deallocated when the flow ends).
//  Holds the draft choices and persists each one as it happens — the
//  anonymous session from splash means nothing is lost before signup.
//

import Foundation

@MainActor
final class OnboardingStore {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let themeStore: ThemeStore

    // Draft state shared across the flow's screens.
    private(set) var firstTaskTitle: String?
    private(set) var selectedThemeId: String
    private(set) var bedtime: BedtimeWindow = .standard
    private(set) var notificationsGranted: Bool?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        themeStore: ThemeStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.themeStore = themeStore
        selectedThemeId = themeStore.current.id
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    func saveFirstTask(title: String) async {
        firstTaskTitle = title
        guard let userId else { return }
        try? await taskRepository.addTask(TaskDraft(title: title), userId: userId)
    }

    func selectTheme(id: String) {
        selectedThemeId = id
        themeStore.apply(themeId: id)
        guard let userId else { return }
        Task { try? await profileRepository.saveThemeId(id, userId: userId) }
    }

    func saveBedtime(_ window: BedtimeWindow) async {
        bedtime = window
        guard let userId else { return }
        try? await profileRepository.saveBedtime(window, userId: userId)
    }

    func saveNotificationChoice(granted: Bool) async {
        notificationsGranted = granted
        guard let userId else { return }
        try? await profileRepository.saveNotificationChoice(granted, userId: userId)
    }

    func saveImportedReminderLists(ids: [String]) async {
        guard let userId else { return }
        try? await profileRepository.saveImportedReminderLists(ids, userId: userId)
    }

    func recordAccountLink(_ account: AuthAccount) async {
        guard let userId else { return }
        try? await profileRepository.saveAccountLink(
            provider: account.providerId ?? "unknown",
            displayName: account.displayName,
            userId: userId
        )
    }

    func recordMembership(isSubscribed: Bool, trialEndsAt: Date?) async {
        guard let userId else { return }
        try? await profileRepository.saveMembershipMirror(
            isSubscribed: isSubscribed,
            trialEndsAt: trialEndsAt,
            userId: userId
        )
    }

    func markComplete() async {
        guard let userId else { return }
        try? await profileRepository.markOnboardingComplete(userId: userId)
    }
}
