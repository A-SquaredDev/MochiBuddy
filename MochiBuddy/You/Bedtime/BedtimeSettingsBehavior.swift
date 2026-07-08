//
//  BedtimeSettingsBehavior.swift
//  MochiBuddy
//

import Foundation

enum BedtimeSettingsBehavior {

    enum EditTarget: Equatable {
        case none
        case bedtime
        case wake
    }

    struct UIState: UpdatableStruct, Equatable {
        var bedtimeText = ""
        var wakeText = ""
        var bedtimeDate = Date()
        var wakeDate = Date()
        var editing: EditTarget = .none
    }

    enum ViewAction {
        case load
        case bedtimeTapped
        case wakeTapped
        case bedtimeChanged(Date)
        case wakeChanged(Date)
    }
}
