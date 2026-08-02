//
//  MeetMochiBehavior.swift
//  MochiBuddy
//

import Foundation

enum MeetMochiBehavior {

    struct Page: Equatable {
        let eyebrow: String?
        let title: String
        let body: String
        let cta: String
        let vitality: Double
        let glow: Bool
        let meterValue: Double?
        let showsCoinBadge: Bool
        /// The closing beat: naming card with the text field and the
        /// quiet keep-the-default secondary. Part of *meeting*, not a new
        /// step (Personal Layer, Feature 1).
        var isNamingBeat = false
    }

    static let pages: [Page] = [
        Page(
            eyebrow: "Meet Mochi",
            title: "This is Mochi.",
            body: "A little friend who keeps an eye on your to-do list. Stay on top of things and Mochi beams, happy dances and all.",
            cta: "Hi, Mochi",
            vitality: 96,
            glow: true,
            meterValue: nil,
            showsCoinBadge: false
        ),
        Page(
            eyebrow: nil,
            title: "Fall behind, and Mochi feels it too.",
            body: "Overdue tasks weigh on Mochi. No scolding, no red badges screaming at you, just a soft nudge that says, let's take care of things.",
            cta: "I get it",
            vitality: 9,
            glow: false,
            meterValue: 12,
            showsCoinBadge: false
        ),
        Page(
            eyebrow: nil,
            title: "Every task you finish lifts Mochi back up.",
            body: "Check one off and watch the mood rise, plus a few coins to spoil Mochi with. Helping Mochi is really just helping you.",
            cta: "Next",
            vitality: 82,
            glow: true,
            meterValue: 82,
            showsCoinBadge: true
        ),
        Page(
            eyebrow: nil,
            title: "They need a name. What will you call them?",
            body: "This little one is yours now. Pick any name you like, or keep the classic.",
            cta: "Let's begin",
            vitality: 90,
            glow: true,
            meterValue: nil,
            showsCoinBadge: false,
            isNamingBeat: true
        ),
    ]

    struct UIState: UpdatableStruct, Equatable {
        var pageIndex = 0
        var page: Page = MeetMochiBehavior.pages[0]
        var canGoBack = false
        /// Live draft in the naming field; committed graphemes only, cap
        /// enforced by the field itself.
        var nameDraft = ""
        var isSaving = false
        /// The naming beat could not mint the session (offline first
        /// run) - drives the connection alert so the adoption is never
        /// silently lost.
        var sessionFailed = false
    }

    enum ViewAction {
        case continueTapped
        case backTapped
        case dismissSessionAlert
        case nameDraftChanged(String)
        /// The quiet "Mochi is perfect" secondary - keeps the default.
        case keepDefaultTapped
    }

    enum NavigationEvent {
        case showFirstTask
    }
}
