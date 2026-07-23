//
//  BedtimeBehavior.swift
//  MochiBuddy
//

import Foundation

enum BedtimeBehavior {

    enum EditTarget: Equatable {
        case none
        case bedtime
        case wake
    }

    struct UIState: UpdatableStruct, Equatable {
        /// The pet's chosen name (named in step 2, so it's already set).
        var petName = "Mochi"
        var bedtimeText = ""
        var wakeText = ""
        var bedtimeDate = Date()
        var wakeDate = Date()
        var editing: EditTarget = .none
        var isSaving = false
    }

    enum ViewAction {
        case load
        case bedtimeTapped
        case wakeTapped
        case bedtimeChanged(Date)
        case wakeChanged(Date)
        case continueTapped
    }

    enum NavigationEvent {
        case next
    }
}
