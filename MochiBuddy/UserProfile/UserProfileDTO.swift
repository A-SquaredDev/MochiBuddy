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
    let bestStreakCount: Int?
    let lastActiveDate: Date?
    let isSubscribed: Bool?
    let trialEndsAt: Date?
    let onboardingComplete: Bool?
    let notificationsEnabled: Bool?
    let notificationPrefs: [String: Any]?
    let soundEnabled: Bool?
    let vacationMode: Bool?
    let vacationResumeAt: Date?
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
        bestStreakCount = data["bestStreakCount"] as? Int
        lastActiveDate = (data["lastActiveDate"] as? Timestamp)?.dateValue()
        isSubscribed = data["isSubscribed"] as? Bool
        trialEndsAt = (data["trialEndsAt"] as? Timestamp)?.dateValue()
        onboardingComplete = data["onboardingComplete"] as? Bool
        notificationsEnabled = data["notificationsEnabled"] as? Bool
        notificationPrefs = data["notificationPrefs"] as? [String: Any]
        soundEnabled = data["soundEnabled"] as? Bool
        vacationMode = data["vacationMode"] as? Bool
        vacationResumeAt = (data["vacationResumeAt"] as? Timestamp)?.dateValue()
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
            bestStreakCount: max(dto.bestStreakCount ?? 0, dto.streakCount ?? 0),
            lastActiveDate: dto.lastActiveDate,
            isSubscribed: dto.isSubscribed ?? false,
            trialEndsAt: dto.trialEndsAt,
            onboardingComplete: dto.onboardingComplete ?? false,
            notificationsEnabled: dto.notificationsEnabled,
            notificationPrefs: notificationPrefs(from: dto.notificationPrefs),
            soundEnabled: dto.soundEnabled ?? false,
            vacationMode: dto.vacationMode ?? false,
            vacationResumeAt: dto.vacationResumeAt,
            importedReminderListIds: dto.importedReminderListIds ?? []
        )
    }

    private static func notificationPrefs(from data: [String: Any]?) -> NotificationPrefs {
        guard let data else { return .standard }
        var prefs = NotificationPrefs.standard
        if let raw = data["level"] as? String, let level = NudgeLevel(rawValue: raw) {
            prefs.level = level
        }
        prefs.taskReminders = data["taskReminders"] as? Bool ?? prefs.taskReminders
        prefs.morningRundown = data["morningRundown"] as? Bool ?? prefs.morningRundown
        prefs.moodDips = data["moodDips"] as? Bool ?? prefs.moodDips
        prefs.bedtimeSilence = data["bedtimeSilence"] as? Bool ?? prefs.bedtimeSilence
        return prefs
    }
}
