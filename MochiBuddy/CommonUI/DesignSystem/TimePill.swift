//
//  TimePill.swift
//  MochiBuddy
//
//  Labelled time value ("BEDTIME / 10:00 PM") that highlights while its
//  wheel picker is open. Shared by onboarding and settings bedtime editors.
//

import SwiftUI

struct TimePill: View {
    let label: String
    let time: String
    let isActive: Bool
    let onTap: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.impact(.light)
            onTap()
        } label: {
            VStack(spacing: 3) {
                Text(label.uppercased())
                    .font(MochiFont.body(10.5, weight: .heavy))
                    .kerning(0.6)
                    .foregroundStyle(theme.muted)
                Text(time)
                    .font(MochiFont.display(21, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(isActive ? theme.primary : theme.line, lineWidth: 1.5)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}
