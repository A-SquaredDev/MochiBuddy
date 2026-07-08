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
        // Row taps routed through the ViewModel so future logic (e.g. gating)
        // stays out of the View.
        case bedtimeTapped
        case statsTapped
        case notificationsTapped
        case remindersTapped
        case vacationTapped
        case manageListsTapped
        case deleteAccountTapped
    }

    enum NavigationEvent {
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
