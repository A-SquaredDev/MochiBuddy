//
//  PaywallBehavior.swift
//  MochiBuddy
//

import Foundation

enum PaywallBehavior {

    struct Hook: Equatable, Identifiable {
        var icon: String? = nil
        /// Custom template asset (the Mochi brand mark) in place of a symbol.
        var iconImage: String? = nil
        let title: String
        let sub: String
        var id: String { title }
    }

    static let hooks: [Hook] = [
        Hook(iconImage: "mochi-mark", title: "Your Mochi, fully alive", sub: "Every mood, reaction & happy dance"),
        Hook(icon: "bell.fill", title: "Gentle nudges that work", sub: "Smart reminders, repeats & morning rundowns"),
        Hook(icon: "paintpalette.fill", title: "All five flavors", sub: "Recolour the whole app anytime"),
        Hook(icon: "gift.fill", title: "Treats, coins & widgets", sub: "Comfort Mochi from your home screen"),
    ]

    struct UIState: UpdatableStruct, Equatable {
        var hooks: [Hook] = PaywallBehavior.hooks
        var plans: [PlanCardModel] = [.yearly, .monthly]
        var selectedPlanId = PlanCardModel.yearly.id
        var ctaTitle = "Start my 14 days free"
        var ctaSubtitle = "Then $29.99/yr · cancel anytime, keep the free days"
        var isPurchasing = false
        var isRestoring = false
        var restoreMessage: String?
    }

    enum ViewAction {
        case load
        case selectPlan(String)
        case startTrialTapped
        case restoreTapped
        case dismissRestoreMessage
    }

    enum NavigationEvent {
        case next
    }
}
