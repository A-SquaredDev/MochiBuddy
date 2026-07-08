//
//  VitalityMeter.swift
//  MochiBuddy
//
//  The pet's health bar — a soft pill track with a gradient fill running
//  accent2 → primary. Optional label row ("Vitality" + "72%") above.
//

import SwiftUI

struct VitalityMeter: View {
    let value: Double // 0–100
    var label: String?
    var showValue = true
    var height: CGFloat = 10

    @Environment(\.mochiTheme) private var theme

    private var fraction: Double { min(max(value, 0), 100) / 100 }

    var body: some View {
        VStack(spacing: 5) {
            if label != nil || showValue {
                HStack(alignment: .firstTextBaseline) {
                    if let label {
                        Text(label)
                            .font(MochiFont.display(11, weight: .medium))
                            .foregroundStyle(theme.ink)
                    }
                    Spacer()
                    if showValue {
                        Text("\(Int(fraction * 100))%")
                            .font(MochiFont.body(11, weight: .heavy))
                            .foregroundStyle(theme.muted)
                            .contentTransition(.numericText())
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.primarySoft)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [theme.accent2, theme.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: height)
            .animation(MochiMotion.bounce, value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Vitality")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
