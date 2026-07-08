//
//  RemindersGateway.swift
//  MochiBuddy
//
//  EventKit access for the optional Apple Reminders import. v1 scope:
//  the user picks which lists Mochi may watch; tasks stay in EventKit
//  (we only store the chosen list ids on the profile).
//

import Foundation
import EventKit

struct ReminderList: Equatable, Identifiable {
    let id: String
    let name: String
    let incompleteCount: Int
}

enum RemindersAccess: Equatable {
    case notDetermined
    case granted
    case denied
}

protocol RemindersGateway: AnyObject {
    var accessStatus: RemindersAccess { get }
    /// Fires the EventKit full-access prompt (needs
    /// NSRemindersFullAccessUsageDescription in Info.plist).
    func requestFullAccess() async -> Bool
    func fetchLists() async -> [ReminderList]
}

final class EventKitRemindersGateway: RemindersGateway {

    private let store = EKEventStore()

    var accessStatus: RemindersAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .granted
        default: .denied
        }
    }

    func requestFullAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func fetchLists() async -> [ReminderList] {
        let calendars = store.calendars(for: .reminder)
        var lists: [ReminderList] = []
        for calendar in calendars {
            let count = await incompleteCount(in: calendar)
            lists.append(ReminderList(
                id: calendar.calendarIdentifier,
                name: calendar.title,
                incompleteCount: count
            ))
        }
        return lists
    }

    private func incompleteCount(in calendar: EKCalendar) async -> Int {
        await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: [calendar]
            )
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.count ?? 0)
            }
        }
    }
}
