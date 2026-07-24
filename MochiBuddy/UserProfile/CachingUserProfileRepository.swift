//
//  CachingUserProfileRepository.swift
//  MochiBuddy
//
//  Decorator over UserProfileRepository: serves the last known profile from
//  memory instantly (settings screens render real values on first frame) and
//  refreshes from the source in the background. Every in-app profile write
//  already flows through this protocol, so write-through keeps the cache
//  coherent; only cross-device edits are ever momentarily stale.
//

import Foundation

final class CachingUserProfileRepository: UserProfileRepository {

    private let wrapped: UserProfileRepository

    private var cached: UserProfile?
    /// Bumped on every cache mutation so an in-flight background refresh
    /// that started earlier can't clobber newer local state.
    private var version = 0
    private(set) var refreshTask: Task<Void, Never>?

    init(wrapping wrapped: UserProfileRepository) {
        self.wrapped = wrapped
    }

    func fetchProfile(userId: String) async throws -> UserProfile? {
        if let cached, cached.id == userId {
            FirestoreReadLog.recordCacheHit(Self.self)
            refreshInBackground(userId: userId)
            return cached
        }
        let profile = try await wrapped.fetchProfile(userId: userId)
        version += 1
        cached = profile
        return profile
    }

    private func refreshInBackground(userId: String) {
        guard refreshTask == nil else { return }
        let startVersion = version
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            guard let profile = try? await self?.wrapped.fetchProfile(userId: userId),
                  let self, version == startVersion
            else { return }
            cached = profile
        }
    }

    /// Applies an in-app write to the cached copy (write-through).
    private func mutate(_ userId: String, _ change: (inout UserProfile) -> Void) {
        guard var profile = cached, profile.id == userId else { return }
        change(&profile)
        version += 1
        cached = profile
    }

    /// Barrier fetch: always hits the source; refreshes the cache with
    /// what the server said (it is by definition the freshest truth).
    func fetchProfileFromServer(userId: String) async throws -> UserProfile? {
        let profile = try await wrapped.fetchProfileFromServer(userId: userId)
        if let profile {
            version += 1
            cached = profile
        }
        return profile
    }

    func ensureProfile(for account: AuthAccount) async throws {
        try await wrapped.ensureProfile(for: account)
    }

    func saveThemeId(_ themeId: String, userId: String) async throws {
        try await wrapped.saveThemeId(themeId, userId: userId)
        mutate(userId) { $0.themeId = themeId }
    }

    func saveBedtime(_ bedtime: BedtimeWindow, userId: String) async throws {
        try await wrapped.saveBedtime(bedtime, userId: userId)
        // Mirror the persistence-boundary sanitizing and timezone stamp.
        mutate(userId) {
            $0.bedtime = bedtime.sanitized
            $0.timezone = TimeZone.current.identifier
        }
    }

    func saveNotificationChoice(_ enabled: Bool, userId: String) async throws {
        try await wrapped.saveNotificationChoice(enabled, userId: userId)
        mutate(userId) { $0.notificationsEnabled = enabled }
    }

    func saveNotificationPrefs(_ prefs: NotificationPrefs, userId: String) async throws {
        try await wrapped.saveNotificationPrefs(prefs, userId: userId)
        mutate(userId) { $0.notificationPrefs = prefs }
    }

    func saveSoundEnabled(_ enabled: Bool, userId: String) async throws {
        try await wrapped.saveSoundEnabled(enabled, userId: userId)
        mutate(userId) { $0.soundEnabled = enabled }
    }

    func saveVacation(mode: Bool, resumeAt: Date?, startedAt: Date?, userId: String) async throws {
        try await wrapped.saveVacation(mode: mode, resumeAt: resumeAt, startedAt: startedAt, userId: userId)
        mutate(userId) {
            $0.vacationMode = mode
            $0.vacationResumeAt = resumeAt
            $0.vacationStartedAt = startedAt
        }
    }

    func saveImportedReminderLists(_ ids: [String], userId: String) async throws {
        try await wrapped.saveImportedReminderLists(ids, userId: userId)
        mutate(userId) { $0.importedReminderListIds = ids }
    }

    func saveAccountLink(provider: String, displayName: String?, userId: String) async throws {
        try await wrapped.saveAccountLink(provider: provider, displayName: displayName, userId: userId)
        mutate(userId) {
            $0.authProvider = provider
            if let displayName {
                $0.displayName = displayName
            }
        }
    }

    func saveDisplayName(_ name: String, userId: String) async throws {
        try await wrapped.saveDisplayName(name, userId: userId)
        mutate(userId) { $0.displayName = name }
    }

    func saveMochiName(_ name: String, userId: String) async throws {
        try await wrapped.saveMochiName(name, userId: userId)
        // Mirror the persistence-boundary sanitizing.
        mutate(userId) { $0.mochiName = PetNameSanitizer.canonicalName(from: name) }
    }

    func stampAdoptedOn(_ dateString: String, userId: String) async throws {
        try await wrapped.stampAdoptedOn(dateString, userId: userId)
        // Write-once: the cache honors an existing value like the rules do.
        mutate(userId) {
            if $0.adoptedOn == nil, AdoptedOnDate.isValid(dateString) {
                $0.adoptedOn = dateString
            }
        }
    }

    func saveObservationIntervals(_ intervals: [ObservationInterval], userId: String) async throws {
        try await wrapped.saveObservationIntervals(intervals, userId: userId)
        mutate(userId) { $0.observationIntervals = intervals }
    }

    func stampObservationLogSince(_ date: Date, userId: String) async throws {
        try await wrapped.stampObservationLogSince(date, userId: userId)
        // Set-once: the cache honors an existing value like the writers do.
        mutate(userId) {
            if $0.observationLogSince == nil {
                $0.observationLogSince = date
            }
        }
    }

    func saveMembershipMirror(isSubscribed: Bool, trialEndsAt: Date?, userId: String) async throws {
        try await wrapped.saveMembershipMirror(isSubscribed: isSubscribed, trialEndsAt: trialEndsAt, userId: userId)
        mutate(userId) {
            $0.isSubscribed = isSubscribed
            if let trialEndsAt {
                $0.trialEndsAt = trialEndsAt
            }
        }
    }

    func markOnboardingComplete(userId: String) async throws {
        try await wrapped.markOnboardingComplete(userId: userId)
        mutate(userId) { $0.onboardingComplete = true }
    }

    func incrementCoins(by delta: Int, userId: String) async throws {
        try await wrapped.incrementCoins(by: delta, userId: userId)
        mutate(userId) { $0.coins += delta }
    }

    func saveStreak(count: Int, best: Int, lastActiveDate: Date, userId: String) async throws {
        try await wrapped.saveStreak(count: count, best: best, lastActiveDate: lastActiveDate, userId: userId)
        mutate(userId) {
            $0.streakCount = count
            $0.bestStreakCount = best
            $0.lastActiveDate = lastActiveDate
        }
    }
}
