//
//  CelebrationCenter.swift
//  MochiBuddy
//
//  Streak-milestone celebrations from every completion surface (Home,
//  Tasks, notification actions, the widget drain) land here, and Home -
//  Mochi's surface - shows them on its next derivation. In-app by design:
//  a milestone only happens on a completion, and completions either
//  happen with the app open or land at drain time on the next open, so a
//  push would always arrive while the user is already looking at Mochi.
//

import Foundation

@MainActor
final class CelebrationCenter {

    private(set) var pendingMilestone: Int?

    /// Keep the biggest pending milestone (a drained widget queue can land
    /// several completions, and only the deepest streak beat matters).
    func post(milestone: Int) {
        pendingMilestone = max(milestone, pendingMilestone ?? 0)
    }

    /// Read-and-clear, for the one surface that shows it.
    func consumeMilestone() -> Int? {
        defer { pendingMilestone = nil }
        return pendingMilestone
    }
}
