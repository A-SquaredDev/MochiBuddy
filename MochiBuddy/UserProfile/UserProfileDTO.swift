//
//  UserProfileDTO.swift
//  MochiBuddy
//
//  Firestore-shaped data for users/{uid} plus the mapper to the domain
//  model. DTOs stay close to the wire format; the mapper owns transformation.
//

import Foundation
import FirebaseFirestore

struct UserProfileDTO {
    let id: String
    let displayName: String?
    let authProvider: String?
    let createdAt: Date?
    let timezone: String?
    let bedtimeStart: Int?
    let bedtimeEnd: Int?
    let themeId: String?
    let coins: Int?
    let streakCount: Int?
    let isSubscribed: Bool?
    let trialEndsAt: Date?
    let onboardingComplete: Bool?
    let notificationsEnabled: Bool?
    let importedReminderListIds: [String]?

    init(id: String, data: [String: Any]) {
        self.id = id
        displayName = data["displayName"] as? String
        authProvider = data["authProvider"] as? String
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        timezone = data["timezone"] as? String
        bedtimeStart = data["bedtimeStart"] as? Int
        bedtimeEnd = data["bedtimeEnd"] as? Int
        themeId = data["themeId"] as? String
        coins = data["coins"] as? Int
        streakCount = data["streakCount"] as? Int
        isSubscribed = data["isSubscribed"] as? Bool
        trialEndsAt = (data["trialEndsAt"] as? Timestamp)?.dateValue()
        onboardingComplete = data["onboardingComplete"] as? Bool
        notificationsEnabled = data["notificationsEnabled"] as? Bool
        importedReminderListIds = data["importedReminderListIds"] as? [String]
    }
}

enum UserProfileMapper {
    static func map(_ dto: UserProfileDTO) -> UserProfile {
        UserProfile(
            id: dto.id,
            displayName: dto.displayName,
            authProvider: dto.authProvider,
            createdAt: dto.createdAt,
            timezone: dto.timezone,
            bedtime: BedtimeWindow(
                startMinutes: dto.bedtimeStart ?? BedtimeWindow.standard.startMinutes,
                endMinutes: dto.bedtimeEnd ?? BedtimeWindow.standard.endMinutes
            ),
            themeId: dto.themeId,
            coins: dto.coins ?? 0,
            streakCount: dto.streakCount ?? 0,
            isSubscribed: dto.isSubscribed ?? false,
            trialEndsAt: dto.trialEndsAt,
            onboardingComplete: dto.onboardingComplete ?? false,
            notificationsEnabled: dto.notificationsEnabled,
            importedReminderListIds: dto.importedReminderListIds ?? []
        )
    }
}
