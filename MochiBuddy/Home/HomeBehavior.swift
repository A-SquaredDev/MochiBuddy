//
//  HomeBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum HomeBehavior {

    struct TodoUIItem: Equatable, Identifiable {
        let id: String
        let title: String
        let meta: String
        let state: TodoRowState
        let chip: String
        var listName: String? = nil
        var listColor: Color? = nil
        var sourceBadge: String? = nil
    }

    struct TreatUIItem: Equatable, Identifiable {
        let id: String
        let name: String
        let liftText: String      // "+18"
        let durationText: String  // "lasts ~3 hr"
        let costText: String      // "Give · 30 ¢"
        let canAfford: Bool
    }

    /// Identifiable wrapper so the editor sheet presents via sheet(item:).
    /// `task: nil` is a new capture - optionally seeded with a draft title
    /// typed into the quick-add field.
    struct EditingTask: Equatable, Identifiable {
        let task: TaskItem?
        var draftTitle: String? = nil
        var id: String { task?.id ?? "new" }
    }

    /// One compact row in the "This week" preview.
    struct WeekPreviewItem: Equatable, Identifiable {
        let id: String        // "d1"…"d6"
        let dayLabel: String  // "Tomorrow" / "Fri"
        let summary: String   // "Gym · Groceries +1 more"
        let count: Int
    }

    /// One "came due while you were away" row in the re-entry triage sheet.
    struct TriageItem: Equatable, Identifiable {
        let id: String
        let title: String
        let meta: String
    }

    struct UIState: UpdatableStruct, Equatable {
        /// True until the first Firestore fetch lands - drives the skeleton.
        var isLoading = true
        /// Lapsed entitlement: the quiet-checklist mode. Mochi naps, coins
        /// and quick-add hide, a Wake Mochi CTA replaces pet/treats.
        var isLapsed = false
        /// billing_grace: fully entitled, plus a soft payment nudge.
        var showBillingBanner = false
        /// Vacation active: resting pose pinned, mood chrome hidden.
        var isOnVacation = false
        /// "back Sat, Jul 25" / "back whenever you're ready" - nil hides it.
        var vacationBanner: String?
        /// Open-ended trip, two weeks in: the gentle "still away?" card.
        var showVacationCheckIn = false
        /// Re-entry triage: the came-due-while-away pile, and the sheet.
        var triageItems: [TriageItem] = []
        var showTriage = false
        var greeting = "Hi, friend"
        var subGreeting = "Let's keep Mochi happy"
        var coins = 0
        var streakDays = 0
        var baseline: Double = MoodEngine.Constants.anchor
        var buffer: Double = 0
        /// baseline + buffer, clamped - what the pet's face shows.
        var displayedMood: Double = MoodEngine.Constants.anchor
        /// Inside the bedtime window - the pet sleeps regardless of vitality.
        var isSleeping = false
        var moodTitle = "Mochi feels content"
        var moodSub = "Clear a task to make it beam"
        /// Sparse streak-milestone banner (7 / 30 / then every 50) - the
        /// in-app celebration surface; nil hides it.
        var celebrationText: String?
        var petSquishTrigger = 0
        var quickAddText = ""
        var todayDateText = ""
        var todayItems: [TodoUIItem] = []
        /// Tasks completed today - their own section under Today.
        var doneTodayItems: [TodoUIItem] = []
        var weekPreview: [WeekPreviewItem] = []
        /// "boost fades in ~12m" - nil when no boost is active.
        var boostFadeText: String?
        var leftText = "0 left"
        var showEmptyToday = false
        var showTreats = false
        var treats: [TreatUIItem] = []
        var bufferLabel = "+0 / 30"
        var petActionMeta = "+8 · lasts ~15 min"
        var editingTask: EditingTask?
    }

    enum ViewAction {
        case refresh
        /// Timer beat - re-derives the decaying buffer, no fetching.
        case tick
        case petTapped
        case treatsTapped
        case dismissTreats
        case giveTreat(String)
        case quickAddChanged(String)
        case quickAddSubmitted
        /// Plus button - opens the full editor seeded with the typed title.
        case composeTapped
        case toggleTask(String)
        case taskTapped(String)
        case editorDismissed
        case dismissCelebration
        // Vacation surfaces.
        case endVacationTapped
        case vacationKeepResting
        case vacationWelcomeBack
        // Re-entry triage.
        case triageComplete(String)
        case triageReschedule(String)
        case triageDismiss(String)
        case triageCompleteAll
        case triageRescheduleAll
        case triageDismissAll
        case triageLater
    }
}
