//
//  MembershipSession.swift
//  MochiBuddy
//
//  The app-wide entitlement snapshot the tab surfaces read synchronously.
//  RevenueCat stays the source of truth; this caches the last status
//  learned (splash, onboarding finish, You-tab refresh). Design doc rule:
//  if RevenueCat says entitled, they're entitled - billing_grace is fully
//  entitled, never a lockout.
//

import Observation

@MainActor
@Observable
final class MembershipSession {

    /// Last-known status. Optimistic default so dev launches that skip the
    /// flow (-mochiStartAtHome) get the full app.
    var status: MembershipStatus = .active(plan: .yearly, renewsAt: nil, willRenew: true) {
        didSet {
            if oldValue != status {
                onChange?()
            }
        }
    }

    /// Fired on a real status change - the container hooks the
    /// notification re-lay here so a lapse or reactivation reshapes the
    /// pending queue immediately, wherever it was learned.
    var onChange: (() -> Void)?

    /// Lapsed mode: the app degrades to a quiet checklist - Mochi asleep,
    /// no coins, no new tasks, no recurrence. Everything else stays usable.
    var isLapsed: Bool {
        switch status {
        case .lapsed, .notSubscribed: true
        case .active, .trial, .billingGrace: false
        }
    }

    /// Apple is retrying a failed charge - fully entitled, plus a gentle
    /// "update payment method" surface. Never treated as a cancellation.
    var hasBillingIssue: Bool {
        if case .billingGrace = status { return true }
        return false
    }
}
