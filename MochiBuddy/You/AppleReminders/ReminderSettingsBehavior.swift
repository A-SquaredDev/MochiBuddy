//
//  ReminderSettingsBehavior.swift
//  MochiBuddy
//

import Foundation

enum ReminderSettingsBehavior {

    struct ListUIItem: Equatable, Identifiable {
        let id: String
        let name: String
        let countText: String
        var isSyncing: Bool
    }

    enum Status: Equatable {
        case loading
        /// EventKit access not granted yet — show the primer + connect CTA.
        case disconnected
        /// Access refused at the OS level — only Settings can undo it.
        case systemDenied
        case connected
    }

    struct UIState: UpdatableStruct, Equatable {
        var status: Status = .loading
        var lists: [ListUIItem] = []
        var syncingCount = 0
        var isConnecting = false
    }

    enum ViewAction {
        case load
        case connectTapped
        case setListSyncing(id: String, isOn: Bool)
        case disconnectTapped
    }
}
