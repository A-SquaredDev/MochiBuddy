//
//  HomePlaceholderView.swift
//  MochiBuddy
//
//  Post-onboarding landing. The full home surface (tasks, coins, mood
//  engine) is the next milestone — this keeps Mochi alive in the meantime.
//

import SwiftUI

struct HomePlaceholderView: View {
    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                VitalityMeter(value: 82, label: "Vitality")
                    .padding(.horizontal, 32)
                MochiPetView(vitality: 82, size: 150)
                VStack(spacing: 4) {
                    Text("Mochi is happy you're here")
                        .font(MochiFont.display(20, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("Your tasks and Mochi's world land here next.\nGive Mochi a tap in the meantime — squish!")
                        .font(MochiFont.body(13, weight: .bold))
                        .lineSpacing(4)
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
    }
}
