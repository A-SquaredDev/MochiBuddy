//
//  RevenueCatMembershipStore.swift
//  MochiBuddy
//
//  The production MembershipStore — StoreKit via RevenueCat, per the design
//  doc. One entitlement ("membership") gates everything; the offering's
//  annual/monthly packages map to MembershipPlan.
//

import Foundation
import RevenueCat

enum RevenueCatConfig {
    static let apiKey = "appl_nVwgWSwmbMYopwKAkoqufPMOGRK"
    static let entitlementID = "membership"

    /// Call once at app launch, before anything touches Purchases.shared.
    static func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }
}

final class RevenueCatMembershipStore: MembershipStore {

    func identify(userId: String) async {
        guard Purchases.shared.appUserID != userId else { return }
        _ = try? await Purchases.shared.logIn(userId)
    }

    func currentStatus() async -> MembershipStatus {
        guard let info = try? await Purchases.shared.customerInfo() else {
            return .notSubscribed
        }
        return Self.status(from: info)
    }

    func planOptions() async -> [MembershipPlanOption] {
        guard let offering = try? await Purchases.shared.offerings().current else {
            return [.defaultYearly, .defaultMonthly]
        }
        var options: [MembershipPlanOption] = []
        if let annual = offering.annual {
            options.append(Self.option(for: .yearly, package: annual))
        }
        if let monthly = offering.monthly {
            options.append(Self.option(for: .monthly, package: monthly))
        }
        return options.isEmpty ? [.defaultYearly, .defaultMonthly] : options
    }

    func restorablePurchase() async -> RestorablePurchase? {
        // syncPurchases quietly re-reads the store receipt — no UI, no charge.
        guard let info = try? await Purchases.shared.syncPurchases(),
              let entitlement = info.entitlements[RevenueCatConfig.entitlementID],
              entitlement.isActive
        else {
            return nil
        }
        return RestorablePurchase(
            plan: Self.plan(fromProductId: entitlement.productIdentifier),
            renewsAt: entitlement.expirationDate
        )
    }

    func startTrial(plan: MembershipPlan) async throws {
        try await purchase(plan: plan)
    }

    func activate(plan: MembershipPlan) async throws {
        try await purchase(plan: plan)
    }

    func restore(_ purchase: RestorablePurchase) async throws {
        let info = try await Purchases.shared.restorePurchases()
        guard info.entitlements[RevenueCatConfig.entitlementID]?.isActive == true else {
            throw MembershipStoreError.nothingToRestore
        }
    }

    private func purchase(plan: MembershipPlan) async throws {
        guard let offering = try? await Purchases.shared.offerings().current,
              let package = plan == .yearly ? offering.annual : offering.monthly
        else {
            throw MembershipStoreError.purchaseFailed
        }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            throw MembershipStoreError.cancelled
        }
        guard result.customerInfo.entitlements[RevenueCatConfig.entitlementID]?.isActive == true else {
            throw MembershipStoreError.purchaseFailed
        }
    }

    private static func status(from info: CustomerInfo) -> MembershipStatus {
        guard let entitlement = info.entitlements[RevenueCatConfig.entitlementID] else {
            return .notSubscribed
        }
        guard entitlement.isActive else {
            // Had the entitlement once, not anymore — the lapsed re-entry path.
            return .lapsed
        }
        if entitlement.periodType == .trial {
            return .trial(endsAt: entitlement.expirationDate ?? .now)
        }
        return .active(
            plan: plan(fromProductId: entitlement.productIdentifier),
            renewsAt: entitlement.expirationDate
        )
    }

    private static func option(for plan: MembershipPlan, package: Package) -> MembershipPlanOption {
        let product = package.storeProduct
        var perMonth: String?
        if plan == .yearly, let monthly = product.pricePerMonth {
            perMonth = product.priceFormatter?.string(from: monthly)
        }
        return MembershipPlanOption(
            plan: plan,
            price: product.price,
            localizedPrice: product.localizedPriceString,
            localizedPricePerMonth: perMonth,
            hasIntroTrial: product.introductoryDiscount?.paymentMode == .freeTrial
        )
    }

    private static func plan(fromProductId productId: String) -> MembershipPlan {
        productId.hasSuffix("1y") || productId.contains("annual") || productId.contains("year")
            ? .yearly
            : .monthly
    }
}
