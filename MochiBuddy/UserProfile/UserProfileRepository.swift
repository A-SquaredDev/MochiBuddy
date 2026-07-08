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
    func saveImportedReminderLists(_ ids: [String], userId: String) async throws
    func saveAccountLink(provider: String, displayName: String?, userId: String) async throws
    func saveMembershipMirror(isSubscribed: Bool, trialEndsAt: Date?, userId: String) async throws
    func markOnboardingComplete(userId: String) async throws
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
        let snapshot = try await document(userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return UserProfileMapper.map(UserProfileDTO(id: userId, data: data))
    }

    func ensureProfile(for account: AuthAccount) async throws {
        let snapshot = try await document(account.uid).getDocument()
        guard !snapshot.exists else { return }
        // Not awaited: with offline persistence on, server acks can be
        // arbitrarily delayed — the local cache applies the write instantly.
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
        try await merge([
            "bedtimeStart": bedtime.startMinutes,
            "bedtimeEnd": bedtime.endMinutes,
            "timezone": TimeZone.current.identifier,
        ], userId: userId)
    }

    func saveNotificationChoice(_ enabled: Bool, userId: String) async throws {
        try await merge(["notificationsEnabled": enabled], userId: userId)
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

    private func merge(_ fields: [String: Any], userId: String) async throws {
        // Not awaited — see ensureProfile. The write lands in the local cache
        // immediately and syncs when the network allows.
        document(userId).setData(fields, merge: true, completion: nil)
    }
}
