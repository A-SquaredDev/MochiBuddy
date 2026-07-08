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
    }

    static let pages: [Page] = [
        Page(
            eyebrow: "Meet Mochi",
            title: "This is Mochi.",
            body: "A little friend who keeps an eye on your to-do list. Stay on top of things and Mochi beams — happy dances and all.",
            cta: "Hi, Mochi 👋",
            vitality: 96,
            glow: true,
            meterValue: nil,
            showsCoinBadge: false
        ),
        Page(
            eyebrow: nil,
            title: "Fall behind, and Mochi feels it too.",
            body: "Overdue tasks weigh on Mochi. No scolding, no red badges screaming at you — just a soft nudge that says, let's take care of things.",
            cta: "I get it",
            vitality: 9,
            glow: false,
            meterValue: 12,
            showsCoinBadge: false
        ),
        Page(
            eyebrow: nil,
            title: "Every task you finish lifts Mochi back up.",
            body: "Check one off and watch the mood rise — plus a few coins to spoil Mochi with. Helping Mochi is really just helping you.",
            cta: "Let's begin",
            vitality: 82,
            glow: true,
            meterValue: 82,
            showsCoinBadge: true
        ),
    ]

    struct UIState: UpdatableStruct, Equatable {
        var pageIndex = 0
        var page: Page = MeetMochiBehavior.pages[0]
        var canGoBack = false
    }

    enum ViewAction {
        case continueTapped
        case backTapped
    }

    enum NavigationEvent {
        case showFirstTask
    }
}
