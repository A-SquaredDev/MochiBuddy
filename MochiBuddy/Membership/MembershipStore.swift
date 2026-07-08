//
//  MembershipStore.swift
//  MochiBuddy
//
//  Subscription state for the membership gate. Mochi is subscription-only:
//  7-day free trial, then yearly/monthly — no freemium tier.
//
//  NOTE: LocalMembershipStore is a device-local stand-in so the whole
//  onboarding + returning-user flow works end to end today. The production
//  implementation is StoreKit via RevenueCat (see mochi-design-doc.md);
//  swap it in behind this same protocol.
//

import Foundation

enum MembershipPlan: String, CaseIterable {
    case yearly
    case monthly

    var durationDays: Int {
        switch self {
        case .yearly: 365
        case .monthly: 30
        }
    }
}

enum MembershipStatus: Equatable {
    case notSubscribed
    case trial(endsAt: Date)
    case active(plan: MembershipPlan, renewsAt: Date?)
    case lapsed
}

struct RestorablePurchase: Equatable {
    let plan: MembershipPlan
    let renewsAt: Date?
}

/// A purchasable plan with store-localized pricing for the paywall.
struct MembershipPlanOption: Equatable {
    let plan: MembershipPlan
    let price: Decimal
    let localizedPrice: String        // "$29.99"
    let localizedPricePerMonth: String? // "$2.50" (yearly only)
    let hasIntroTrial: Bool
}

enum MembershipStoreError: Error {
    /// The user dismissed the purchase sheet — not an error to surface.
    case cancelled
    case purchaseFailed
    case nothingToRestore
}

protocol MembershipStore: AnyObject {
    /// Ties purchases to the signed-in user so they follow the account.
    func identify(userId: String) async
    func currentStatus() async -> MembershipStatus
    /// Plans with live store pricing (falls back to defaults offline).
    func planOptions() async -> [MembershipPlanOption]
    /// An active purchase on the store account that this install can restore.
    func restorablePurchase() async -> RestorablePurchase?
    func startTrial(plan: MembershipPlan) async throws
    func activate(plan: MembershipPlan) async throws
    func restore(_ purchase: RestorablePurchase) async throws
}

extension MembershipPlanOption {
    /// Hardcoded fallbacks — used by the local stub and when the store
    /// can't be reached before the paywall renders.
    static let defaultYearly = MembershipPlanOption(
        plan: .yearly, price: 29.99, localizedPrice: "$29.99",
        localizedPricePerMonth: "$2.50", hasIntroTrial: true
    )
    static let defaultMonthly = MembershipPlanOption(
        plan: .monthly, price: 3.99, localizedPrice: "$3.99",
        localizedPricePerMonth: nil, hasIntroTrial: true
    )
}

final class LocalMembershipStore: MembershipStore {

    private enum Key {
        static let plan = "membership.plan"
        static let expiresAt = "membership.expiresAt"
        static let isTrial = "membership.isTrial"
        static let everSubscribed = "membership.everSubscribed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func identify(userId: String) async {}

    func planOptions() async -> [MembershipPlanOption] {
        [.defaultYearly, .defaultMonthly]
    }

    func currentStatus() async -> MembershipStatus {
        guard
            let planRaw = defaults.string(forKey: Key.plan),
            let plan = MembershipPlan(rawValue: planRaw),
            let expiresAt = defaults.object(forKey: Key.expiresAt) as? Date
        else {
            return defaults.bool(forKey: Key.everSubscribed) ? .lapsed : .notSubscribed
        }

        guard expiresAt > .now else {
            return .lapsed
        }
        return defaults.bool(forKey: Key.isTrial)
            ? .trial(endsAt: expiresAt)
            : .active(plan: plan, renewsAt: expiresAt)
    }

    func restorablePurchase() async -> RestorablePurchase? {
        // Simulated for development: launch with -mochiSimulateRestorable to
        // exercise the R2 restore flow. RevenueCat's restorePurchases replaces this.
        guard ProcessInfo.processInfo.arguments.contains("-mochiSimulateRestorable") else {
            return nil
        }
        return RestorablePurchase(
            plan: .yearly,
            renewsAt: Calendar.current.date(byAdding: .month, value: 8, to: .now)
        )
    }

    func startTrial(plan: MembershipPlan) async throws {
        let trialEnd = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        defaults.set(plan.rawValue, forKey: Key.plan)
        defaults.set(trialEnd, forKey: Key.expiresAt)
        defaults.set(true, forKey: Key.isTrial)
        defaults.set(true, forKey: Key.everSubscribed)
    }

    func activate(plan: MembershipPlan) async throws {
        let expiry = Calendar.current.date(byAdding: .day, value: plan.durationDays, to: .now) ?? .now
        defaults.set(plan.rawValue, forKey: Key.plan)
        defaults.set(expiry, forKey: Key.expiresAt)
        defaults.set(false, forKey: Key.isTrial)
        defaults.set(true, forKey: Key.everSubscribed)
    }

    func restore(_ purchase: RestorablePurchase) async throws {
        defaults.set(purchase.plan.rawValue, forKey: Key.plan)
        defaults.set(purchase.renewsAt ?? Date.distantFuture, forKey: Key.expiresAt)
        defaults.set(false, forKey: Key.isTrial)
        defaults.set(true, forKey: Key.everSubscribed)
    }
}
