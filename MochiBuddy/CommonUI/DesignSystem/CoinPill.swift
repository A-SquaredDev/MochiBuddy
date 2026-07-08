//
//  CoinPill.swift
//  MochiBuddy
//
//  Coin balance pill — the ¢ badge on a soft tinted capsule. Coins are
//  earned, never bought; this is glanceable balance, not a store button.
//

import SwiftUI

struct CoinPill: View {
    let coins: Int

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Text("¢")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.primaryInk)
                .frame(width: 18, height: 18)
                .background(
                    LinearGradient(
                        colors: [theme.accent2, theme.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
            Text("\(coins)")
                .font(MochiFont.body(12, weight: .heavy))
                .foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
        }
        .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 10))
        .background(theme.primarySoft, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coins) coins")
    }
}
