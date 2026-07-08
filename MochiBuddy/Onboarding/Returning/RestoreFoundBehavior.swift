//
//  RestoreFoundBehavior.swift
//  MochiBuddy
//

import Foundation

enum RestoreFoundBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var planLine = ""
        var renewsLine = ""
        var isWorking = false
        var showAppleIdNote = false
    }

    enum ViewAction {
        case load
        case restoreTapped
        case differentAppleIdTapped
        case dismissAppleIdNote
    }

    enum NavigationEvent {
        case showSuccess
    }
}
