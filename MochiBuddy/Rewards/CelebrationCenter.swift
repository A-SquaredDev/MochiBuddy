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
    /// Rendered anniversary banner text (Personal Layer, Feature 2) -
    /// posted at most once per milestone by MemoriesService, which owns
    /// the once-per-day ledger and the same-date collision rule (a
    /// streak milestone always outranks it, so this slot is only ever
    /// filled on a streak-free date).
    private(set) var pendingAnniversaryText: String?

    /// Keep the biggest pending milestone (a drained widget queue can land
    /// several completions, and only the deepest streak beat matters).
    func post(milestone: Int) {
        pendingMilestone = max(milestone, pendingMilestone ?? 0)
    }

    func post(anniversaryText: String) {
        pendingAnniversaryText = anniversaryText
    }

    /// Read-and-clear, for the one surface that shows it.
    func consumeMilestone() -> Int? {
        defer { pendingMilestone = nil }
        return pendingMilestone
    }

    func consumeAnniversary() -> String? {
        defer { pendingAnniversaryText = nil }
        return pendingAnniversaryText
    }
}
