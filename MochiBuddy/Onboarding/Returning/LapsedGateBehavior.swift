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
        case dismissRestoreMessage
    }

    enum NavigationEvent {
        case enterApp
        case showRestoreFound(RestorablePurchase)
    }
}
