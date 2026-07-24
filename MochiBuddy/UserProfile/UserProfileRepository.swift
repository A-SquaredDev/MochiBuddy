//
//  UserProfileRepository.swift
//  MochiBuddy
//
//  Abstracts the users/{uid} Firestore document behind a domain-aligned API.
//  Onboarding saves each choice as it happens (anonymous-first).
//

import Foundation
import FirebaseFirestore

protocol UserProfileRepository: AnyObject {
    func fetchProfile(userId: String) async throws -> UserProfile?
    /// Creates the profile document on first launch (no-op when it exists).
    func ensureProfile(for account: AuthAccount) async throws
    func saveThemeId(_ themeId: String, userId: String) async throws
    func saveBedtime(_ bedtime: BedtimeWindow, userId: String) async throws
    func saveNotificationChoice(_ enabled: Bool, userId: String) async throws
    func saveNotificationPrefs(_ prefs: NotificationPrefs, userId: String) async throws
    func saveSoundEnabled(_ enabled: Bool, userId: String) async throws
    func saveVacation(mode: Bool, resumeAt: Date?, startedAt: Date?, userId: String) async throws
    func saveImportedReminderLists(_ ids: [String], userId: String) async throws
    func saveAccountLink(provider: String, displayName: String?, userId: String) async throws
    func saveDisplayName(_ name: String, userId: String) async throws
    /// Persists the pet's name (sanitized at this boundary).
    func saveMochiName(_ name: String, userId: String) async throws
    /// Stamps the write-once adoption date. Client code never overwrites an
    /// existing value (courtesy); the security rules are the guarantee.
    func stampAdoptedOn(_ dateString: String, userId: String) async throws
    func saveMembershipMirror(isSubscribed: Bool, trialEndsAt: Date?, userId: String) async throws
    /// Rewrites the observation interval log (append/close discipline is
    /// the recorder's job; the log stays small - entries only accrue on
    /// vacation/lapse transitions).
    func saveObservationIntervals(_ intervals: [ObservationInterval], userId: String) async throws
    /// Stamps when the interval log began. Set-once: client code never
    /// overwrites an existing value (days before it are honestly unknown).
    func stampObservationLogSince(_ date: Date, userId: String) async throws
    func markOnboardingComplete(userId: String) async throws
    /// Atomic coin adjustment (completions earn, treats spend).
    func incrementCoins(by delta: Int, userId: String) async throws
    func saveStreak(count: Int, best: Int, lastActiveDate: Date, userId: String) async throws
}

final class FirestoreUserProfileRepository: UserProfileRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func document(_ userId: String) -> DocumentReference {
        firestore.collection("users").document(userId)
    }

    func fetchProfile(userId: String) async throws -> UserProfile? {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await document(userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return UserProfileMapper.map(UserProfileDTO(id: userId, data: data))
    }

    func ensureProfile(for account: AuthAccount) async throws {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await document(account.uid).getDocument()
        guard !snapshot.exists else { return }
        // Not awaited: with offline persistence on, server acks can be
        // arbitrarily delayed - the local cache applies the write instantly.
        document(account.uid).setData([
            "createdAt": FieldValue.serverTimestamp(),
            "authProvider": account.isAnonymous ? "anonymous" : (account.providerId ?? "unknown"),
            "timezone": TimeZone.current.identifier,
            "coins": 0,
            "streakCount": 0,
            "isSubscribed": false,
            "onboardingComplete": false,
        ], completion: nil)
    }

    func saveThemeId(_ themeId: String, userId: String) async throws {
        try await merge(["themeId": themeId], userId: userId)
    }

    func saveBedtime(_ bedtime: BedtimeWindow, userId: String) async throws {
        // Never persist a zero-length window - sleep must always enforce
        // SOME quiet hours (doc edge case).
        let window = bedtime.sanitized
        try await merge([
            "bedtimeStart": window.startMinutes,
            "bedtimeEnd": window.endMinutes,
            "timezone": TimeZone.current.identifier,
        ], userId: userId)
    }

    func saveNotificationChoice(_ enabled: Bool, userId: String) async throws {
        try await merge(["notificationsEnabled": enabled], userId: userId)
    }

    func saveNotificationPrefs(_ prefs: NotificationPrefs, userId: String) async throws {
        try await merge([
            "notificationPrefs": [
                "taskReminders": prefs.taskReminders,
                "morningRundown": prefs.morningRundown,
                "moodDips": prefs.moodDips,
                "bedtimeSilence": prefs.bedtimeSilence,
                "hideTaskNames": prefs.hideTaskNames,
            ],
        ], userId: userId)
    }

    func saveSoundEnabled(_ enabled: Bool, userId: String) async throws {
        try await merge(["soundEnabled": enabled], userId: userId)
    }

    func saveVacation(mode: Bool, resumeAt: Date?, startedAt: Date?, userId: String) async throws {
        var fields: [String: Any] = ["vacationMode": mode]
        fields["vacationResumeAt"] = resumeAt.map(Timestamp.init(date:)) ?? FieldValue.delete()
        fields["vacationStartedAt"] = startedAt.map(Timestamp.init(date:)) ?? FieldValue.delete()
        try await merge(fields, userId: userId)
    }

    func saveImportedReminderLists(_ ids: [String], userId: String) async throws {
        try await merge(["importedReminderListIds": ids], userId: userId)
    }

    func saveAccountLink(provider: String, displayName: String?, userId: String) async throws {
        var fields: [String: Any] = ["authProvider": provider]
        if let displayName {
            fields["displayName"] = displayName
        }
        try await merge(fields, userId: userId)
    }

    func saveDisplayName(_ name: String, userId: String) async throws {
        try await merge(["displayName": name], userId: userId)
    }

    func saveMochiName(_ name: String, userId: String) async throws {
        try await merge(["mochiName": PetNameSanitizer.canonicalName(from: name)], userId: userId)
    }

    func stampAdoptedOn(_ dateString: String, userId: String) async throws {
        guard AdoptedOnDate.isValid(dateString) else { return }
        try await merge(["adoptedOn": dateString], userId: userId)
    }

    func saveObservationIntervals(_ intervals: [ObservationInterval], userId: String) async throws {
        try await merge([
            "observationIntervals": intervals.map { interval in
                var fields: [String: Any] = [
                    "kind": interval.kind.rawValue,
                    "start": Timestamp(date: interval.start),
                ]
                if let end = interval.end {
                    fields["end"] = Timestamp(date: end)
                }
                return fields
            },
        ], userId: userId)
    }

    func stampObservationLogSince(_ date: Date, userId: String) async throws {
        try await merge(["observationLogSince": Timestamp(date: date)], userId: userId)
    }

    func saveMembershipMirror(isSubscribed: Bool, trialEndsAt: Date?, userId: String) async throws {
        var fields: [String: Any] = ["isSubscribed": isSubscribed]
        if let trialEndsAt {
            fields["trialEndsAt"] = Timestamp(date: trialEndsAt)
        }
        try await merge(fields, userId: userId)
    }

    func markOnboardingComplete(userId: String) async throws {
        try await merge(["onboardingComplete": true], userId: userId)
    }

    func incrementCoins(by delta: Int, userId: String) async throws {
        try await merge(["coins": FieldValue.increment(Int64(delta))], userId: userId)
    }

    func saveStreak(count: Int, best: Int, lastActiveDate: Date, userId: String) async throws {
        try await merge([
            "streakCount": count,
            "bestStreakCount": best,
            "lastActiveDate": Timestamp(date: lastActiveDate),
        ], userId: userId)
    }

    private func merge(_ fields: [String: Any], userId: String) async throws {
        // Not awaited - see ensureProfile. The write lands in the local cache
        // immediately and syncs when the network allows.
        document(userId).setData(fields, merge: true, completion: nil)
    }
}
