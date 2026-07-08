//
//  PlanCard.swift
//  MochiBuddy
//
//  Membership plan option card, shared by the paywall and the lapsed gate.
//

import SwiftUI

struct PlanCardModel: Equatable, Identifiable {
    let id: String
    let name: String
    let price: String
    let per: String
    let note: String
    let badge: String?

    static let yearly = PlanCardModel(
        id: MembershipPlan.yearly.rawValue,
        name: "Yearly",
        price: "$29.99",
        per: "/yr",
        note: "Just $2.50/mo · save 37%",
        badge: "Best value"
    )

    static let monthly = PlanCardModel(
        id: MembershipPlan.monthly.rawValue,
        name: "Monthly",
        price: "$3.99",
        per: "/mo",
        note: "Cancel whenever",
        badge: nil
    )

    /// Presenter helper — maps a store-priced plan option into the card.
    /// `monthlyPrice` (the other plan's raw price) powers the savings note.
    static func from(_ option: MembershipPlanOption, monthlyPrice: Decimal?) -> PlanCardModel {
        switch option.plan {
        case .yearly:
            var note = "Everything included"
            if let perMonth = option.localizedPricePerMonth {
                note = "Just \(perMonth)/mo"
            }
            if let monthlyPrice, monthlyPrice > 0, option.price > 0 {
                let yearOfMonthly = NSDecimalNumber(decimal: monthlyPrice * 12).doubleValue
                let yearly = NSDecimalNumber(decimal: option.price).doubleValue
                let savings = Int(((1 - yearly / yearOfMonthly) * 100).rounded())
                if savings > 0 {
                    note += " · save \(savings)%"
                }
            }
            return PlanCardModel(
                id: option.plan.rawValue, name: "Yearly",
                price: option.localizedPrice, per: "/yr",
                note: note, badge: "Best value"
            )
        case .monthly:
            return PlanCardModel(
                id: option.plan.rawValue, name: "Monthly",
                price: option.localizedPrice, per: "/mo",
                note: "Cancel whenever", badge: nil
            )
        }
    }
}

struct PlanCard: View {
    let model: PlanCardModel
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(MochiFont.display(13.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(model.price)
                        .font(MochiFont.display(20, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(model.per)
                        .font(MochiFont.body(10.5, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
                Text(model.note)
                    .font(MochiFont.body(10.5, weight: .bold))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
            .background(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .fill(isSelected ? theme.primarySoft : theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(isSelected ? theme.primary : theme.line, lineWidth: 2)
            )
            .overlay(alignment: .topLeading) {
                if let badge = model.badge {
                    Text(badge)
                        .font(MochiFont.display(10, weight: .medium))
                        .foregroundStyle(theme.primaryInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(theme.primary, in: Capsule())
                        .offset(x: 12, y: -9)
                }
            }
            .shadow(color: isSelected ? Color.black.opacity(0.14) : .clear, radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .animation(MochiMotion.soft, value: isSelected)
    }
}
