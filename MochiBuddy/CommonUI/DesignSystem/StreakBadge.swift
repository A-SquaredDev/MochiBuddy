//
//  StreakBadge.swift
//  MochiBuddy
//
//  A small pill celebrating consecutive active days — 🔥 4 day.
//

import SwiftUI

struct StreakBadge: View {
    let days: Int
    var unit = "day"
    var icon = "🔥"

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 11))
            Text("\(days) \(unit)")
                .font(MochiFont.body(11, weight: .heavy))
                .foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
        }
        .padding(EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9))
        .background(theme.primarySoft, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(days) \(unit) streak")
    }
}
