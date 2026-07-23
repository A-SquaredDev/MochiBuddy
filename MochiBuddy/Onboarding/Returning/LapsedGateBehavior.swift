//
//  LapsedGateBehavior.swift
//  MochiBuddy
//

import Foundation

enum LapsedGateBehavior {

    struct Stat: Equatable, Identifiable {
        let icon: String
        let value: String
        let label: String
        var id: String { label }
    }

    struct UIState: UpdatableStruct, Equatable {
        /// The pet's chosen name - "Mochi" until the profile loads.
        var petName = "Mochi"
        var stats: [Stat] = []
        var plans: [PlanCardModel] = [.yearly, .monthly]
        var selectedPlanId = PlanCardModel.yearly.id
        var isWorking = false
        var restoreMessage: String?
    }

    enum ViewAction {
        case load
        case selectPlan(String)
        case reactivateTapped
        case restoreTapped
        /// "Not now" - into the app as a quiet checklist, Mochi asleep.
        case continueWithoutTapped
        case dismissRestoreMessage
    }

    enum NavigationEvent: Equatable {
        case enterApp
        case showRestoreFound(RestorablePurchase)
    }
}
