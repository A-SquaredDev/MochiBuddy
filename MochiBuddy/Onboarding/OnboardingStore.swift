//
//  OnboardingStore.swift
//  MochiBuddy
//
//  Scoped shared store for the onboarding flow (created by the Router,
//  injected into the flow's ViewModels, deallocated when the flow ends).
//  Holds the draft choices and persists each one as it happens - the
//  anonymous session from splash means nothing is lost before signup.
//

import Foundation

@MainActor
final class OnboardingStore {

    private let authRepository: AuthRepository
    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let themeStore: ThemeStore
    private let petIdentityStore: PetIdentityStore

    // Draft state shared across the flow's screens.
    private(set) var firstTaskTitle: String?
    private(set) var selectedThemeId: String
    private(set) var bedtime: BedtimeWindow = .standard
    private(set) var notificationsGranted: Bool?

    init(
        authRepository: AuthRepository,
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        themeStore: ThemeStore,
        petIdentityStore: PetIdentityStore
    ) {
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.themeStore = themeStore
        self.petIdentityStore = petIdentityStore
        selectedThemeId = themeStore.current.id
    }

    private var userId: String? { authRepository.currentAccount?.uid }

    /// The wizard's writes need a session, and Landing entries arrive
    /// without one (splash no longer mints). Idempotent: true when a
    /// session exists or was just created; false means offline with
    /// nothing created - the caller surfaces the retry instead of letting
    /// choices vanish into a sessionless flow.
    func ensureSession() async -> Bool {
        (try? await authRepository.ensureSession()) != nil
    }

    /// The chosen pet name, live from the naming beat onward - the very
    /// next screen's copy uses it (instant proof the choice took).
    var petName: String { petIdentityStore.name }

    /// The naming beat (either button): sanitize + persist the name and
    /// stamp the write-once adoptedOn. Skip/keep-default passes "".
    func completeNamingBeat(rawName: String) async {
        guard let userId else { return }
        await petIdentityStore.completeNamingBeat(rawName: rawName, userId: userId)
    }

    func saveFirstTask(title: String, dueAt: Date? = nil, hasTime: Bool = false) async {
        firstTaskTitle = title
        guard let userId else { return }
        var draft = TaskDraft(title: title)
        draft.dueAt = dueAt
        draft.hasTime = hasTime
        _ = try? await taskRepository.addTask(draft, userId: userId)
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
