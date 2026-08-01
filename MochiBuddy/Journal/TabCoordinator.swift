//
//  TabCoordinator.swift
//  MochiBuddy
//
//  Programmatic tab selection plus the letter handoff into the Journal:
//  the Home envelope and letter-notification taps both land here, survive
//  until the tab shell is mounted, and are consumed by the Journal (which
//  resolves the stable letter id and pushes the detail). Feature 6's
//  navigation-only promise: same ids, new destination.
//

import Foundation
import Observation

@MainActor
@Observable
final class TabCoordinator {

    enum LetterRouteSource: Equatable {
        case envelope
        case notification
    }

    struct PendingLetterRoute: Equatable {
        let letterId: String
        let source: LetterRouteSource
    }

    // "-mochiStartTab journal" (dev launch arg, argument-domain parsing)
    // picks the initial tab, same as the old MainTabView-local state.
    var selected: MainTab =
        MainTab(rawValue: UserDefaults.standard.string(forKey: "mochiStartTab") ?? "") ?? .home
    {
        didSet {
            guard selected == .journal, oldValue != .journal,
                  pendingLetterRoute == nil
            else { return }
            telemetry?.log(.opened(source: .tab))
        }
    }

    /// Waiting for the Journal to consume - set before the tab switch so
    /// the didSet above knows this open was routed, not browsed.
    private(set) var pendingLetterRoute: PendingLetterRoute?

    /// Bumped by RootView once its foreground pipeline (widget drain,
    /// entitlement, task-cache refresh) has finished. Tab views re-derive
    /// on this instead of running their own scenePhase refreshes, so one
    /// foreground pays one set of real queries and every tab reads the
    /// warm caches - in the right order, after the drain.
    private(set) var foregroundPulse = 0

    func pulseForeground() {
        foregroundPulse += 1
    }

    private let telemetry: JournalTelemetry?

    init(telemetry: JournalTelemetry? = nil) {
        self.telemetry = telemetry
    }

    func openLetterInJournal(_ letterId: String, source: LetterRouteSource) {
        pendingLetterRoute = PendingLetterRoute(letterId: letterId, source: source)
        telemetry?.log(.opened(source: source == .envelope ? .envelope : .notification))
        selected = .journal
    }

    func consumePendingLetterRoute() -> PendingLetterRoute? {
        defer { pendingLetterRoute = nil }
        return pendingLetterRoute
    }
}
