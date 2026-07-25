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
        /// The pet's name - drives every pet-referential line on this tab.
        var mochiName = "Mochi"
        /// "Met on July 22, 2026", rendered verbatim from the date-only
        /// adoptedOn (no timezone math). Empty until the profile loads.
        var adoptedOnText = ""
        var showMochiRename = false
        var mochiNameDraft = ""
        /// Wake CTA label: name included when it fits the layout,
        /// verb-only otherwise (VoiceOver always gets the full name).
        var wakeCtaTitle = "Wake Mochi"
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
        // Pet rename - available in EVERY state incl. lapsed (a pure text
        // fix wakes nothing, unlocks nothing, schedules nothing).
        case renameMochiTapped
        case mochiNameDraftChanged(String)
        case confirmRenameMochi
        case cancelRenameMochi
        // Row taps routed through the ViewModel so future logic (e.g. gating)
        // stays out of the View.
        case bedtimeTapped
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
        case showNotifications
        case showReminders
        case showVacation
        case showManageLists
        case startDeleteFlow
        case signedOut
    }
}
