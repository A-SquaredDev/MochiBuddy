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
    /// The EKCalendar's color, hex-encoded - nil when unavailable.
    var colorHex: String? = nil
}

/// A lightweight, EventKit-free snapshot of one reminder. EKReminder and
/// EKCalendar never leave this file.
struct ReminderTaskItem: Equatable, Identifiable {
    let id: String          // EKReminder.calendarItemIdentifier
    let title: String
    let dueAt: Date?
    let hasTime: Bool
    let listId: String      // owning EKCalendar's calendarIdentifier
    let listName: String
    var completed: Bool
}

enum RemindersAccess: Equatable {
    case notDetermined
    case granted
    case denied
}

protocol RemindersGateway: AnyObject {
    var accessStatus: RemindersAccess { get }
    /// Fired (on the main actor) when the reminders database changes
    /// underneath us - an edit in the Reminders app, Siri, or another
    /// device. The re-lay trigger; coalesced bursts are absorbed by the
    /// orchestrator's debounce.
    var onExternalChange: (() -> Void)? { get set }
    /// Fires the EventKit full-access prompt (needs
    /// NSRemindersFullAccessUsageDescription in Info.plist).
    func requestFullAccess() async -> Bool
    func fetchLists() async -> [ReminderList]
    /// Open reminders in the given lists. Empty when access isn't granted.
    func fetchOpenReminders(listIds: [String]) async -> [ReminderTaskItem]
    /// Writes completion back to Apple Reminders. False when the item
    /// vanished or the save failed - callers should revert their optimistic
    /// flip.
    func setReminderCompleted(id: String, completed: Bool) async -> Bool
}

final class EventKitRemindersGateway: RemindersGateway {

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    var onExternalChange: (() -> Void)?

    init() {
        // EKEventStoreChanged is posted per-store; observing our own store
        // catches edits made in Apple Reminders, by Siri, or on another
        // device. refreshSourcesIfNecessary keeps this store's snapshot of
        // the database current before anyone re-fetches.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.store.refreshSourcesIfNecessary()
            self?.onExternalChange?()
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

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
            let count = await incompleteReminders(in: [calendar]).count
            lists.append(ReminderList(
                id: calendar.calendarIdentifier,
                name: calendar.title,
                incompleteCount: count,
                colorHex: Self.hexString(from: calendar.cgColor)
            ))
        }
        return lists
    }

    func fetchOpenReminders(listIds: [String]) async -> [ReminderTaskItem] {
        guard accessStatus == .granted else { return [] }
        let calendars = listIds.compactMap { store.calendar(withIdentifier: $0) }
        guard !calendars.isEmpty else { return [] }
        return await incompleteReminders(in: calendars).map { reminder in
            ReminderTaskItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                dueAt: reminder.dueDateComponents?.date,
                hasTime: reminder.dueDateComponents?.hour != nil,
                listId: reminder.calendar?.calendarIdentifier ?? "",
                listName: reminder.calendar?.title ?? "Reminders",
                completed: reminder.isCompleted
            )
        }
    }

    func setReminderCompleted(id: String, completed: Bool) async -> Bool {
        guard accessStatus == .granted,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return false }
        // isCompleted manages completionDate itself.
        reminder.isCompleted = completed
        return (try? store.save(reminder, commit: true)) != nil
    }

    private func incompleteReminders(in calendars: [EKCalendar]) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private static func hexString(from cgColor: CGColor?) -> String? {
        guard let components = cgColor?.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        )?.components, components.count >= 3 else { return nil }
        let r = Int(round(components[0] * 255))
        let g = Int(round(components[1] * 255))
        let b = Int(round(components[2] * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
