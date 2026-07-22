//
//  YouBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum YouBehavior {

    /// One flavor dot in the flavor card.
    struct FlavorSwatch: Equatable, Identifiable {
        let id: String
        let color: Color
    }

    struct UIState: UpdatableStruct, Equatable {
        var displayName = "Mochi friend"
        var identitySub = ""
        var avatarLetter = "M"
        /// Shows the Mochi+ badge on the identity row.
        var isMember = false
        /// Lapsed: flavors lock, Mochi-care rows hide, a Wake Mochi card
        /// appears. Account & legal stay fully functional (non-negotiable).
        var isLapsed = false
        /// billing_grace: entitled, plus the payment-method nudge line.
        var hasBillingIssue = false
        var coins = 0
        var flavors: [FlavorSwatch] = []
        var selectedFlavorId = ""
        var bedtimeText = ""
        var morningRundown = true
        var soundEnabled = false
        var notificationsSub = ""
        var remindersSub = ""
        var vacationSub = ""
        var listsSub = ""
        var subscriptionSub = ""
        var appVersion = ""
        var isRestoring = false
        var restoreMessage: String?
        var showSignOutConfirm = false
        var showNameEditor = false
        var nameDraft = ""
    }

    enum ViewAction {
        case refresh
        case selectFlavor(String)
        case setMorningRundown(Bool)
        case setSoundEnabled(Bool)
        case restoreTapped
        case dismissRestoreMessage
        case signOutTapped
        case confirmSignOut
        case cancelSignOut
        case editNameTapped
        case nameDraftChanged(String)
        case confirmEditName
        case cancelEditName
        // Row taps routed through the ViewModel so future logic (e.g. gating)
        // stays out of the View.
        case bedtimeTapped
        case statsTapped
        case notificationsTapped
        case remindersTapped
        case vacationTapped
        case manageListsTapped
        case deleteAccountTapped
        case wakeMochiTapped
        #if DEBUG
        case devSchedulerTapped
        #endif
    }

    enum NavigationEvent {
        case wakeMochi
        #if DEBUG
        case showDevScheduler
        #endif
        case editBedtime
        case showStats
        case showNotifications
        case showReminders
        case showVacation
        case showManageLists
        case startDeleteFlow
        case signedOut
    }
}
