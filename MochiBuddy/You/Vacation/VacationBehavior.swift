//
//  VacationBehavior.swift
//  MochiBuddy
//

import Foundation

enum VacationBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var isOn = false
        var toggleSub = ""
        var autoResume = false
        var resumeDate = Date()
        var minimumResumeDate = Date()
    }

    enum ViewAction {
        case load
        case setVacation(Bool)
        case setAutoResume(Bool)
        case resumeDateChanged(Date)
        case turnOffTapped
    }
}
