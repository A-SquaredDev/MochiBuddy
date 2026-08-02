//
//  FinishView.swift
//  MochiBuddy
//
//  10 · You're all set: widget nudge, then into the app. Static screen:
//  navigation goes straight through the Router.
//

import SwiftUI

struct FinishView: View {
    let router: any OnboardingRouting
    /// Pet-referential copy only - "Add the Mochi widget" and "Enter
    /// Mochi" below are brand and stay literal.
    var petName = "Mochi"

    @Environment(\.mochiTheme) private var theme
    @State private var showWidgetHelp = false

    var body: some View {
        OnbScaffold {
            VStack(spacing: 4) {
                MochiPetView(vitality: 96, size: 104, petName: petName)
                OnbHeading(
                    eyebrow: "You're all set",
                    title: "Keep \(petName) where you'll see it",
                    bodyText: "A home-screen widget shows \(petName) and your next task at a glance. It's the single best way to stay on track."
                )
            }
            widgetPreviews
                .onLoad { Haptics.success() }
        } footer: {
            MochiButton(title: "Add the Mochi widget") {
                showWidgetHelp = true
            }
            MochiTextLink(title: "Enter Mochi →", strong: true) {
                router.finishOnboarding()
            }
        }
        .sheet(isPresented: $showWidgetHelp) {
            WidgetHelpSheet {
                showWidgetHelp = false
                router.finishOnboarding()
            }
            .presentationDetents([.medium])
            .environment(\.mochiTheme, theme)
        }
    }

    private var widgetPreviews: some View {
        HStack(spacing: 12) {
            // small mood widget
            VStack(spacing: 4) {
                MochiPetView(vitality: 88, size: 62, squishOnTap: false)
                Text("Beaming")
                    .font(MochiFont.display(11, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }
            .frame(width: 118, height: 118)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 13, y: 10)

            // medium: mood + next task
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    MochiPetView(vitality: 88, size: 34, squishOnTap: false)
                    Text("2 left today")
                        .font(MochiFont.display(11.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                }
                Spacer()
                VitalityMeter(value: 88, showValue: false, height: 7)
                Spacer()
                Text("Next · Book the dentist")
                    .font(MochiFont.body(11, weight: .heavy))
                    .foregroundStyle(theme.muted)
            }
            .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
            .frame(width: 118, height: 118)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 13, y: 10)
        }
        .accessibilityHidden(true)
    }
}
