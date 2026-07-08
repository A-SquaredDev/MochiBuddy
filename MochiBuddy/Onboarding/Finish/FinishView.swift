//
//  FinishView.swift
//  MochiBuddy
//
//  10 · You're all set — widget nudge, then into the app. Static screen:
//  navigation goes straight through the Router.
//

import SwiftUI

struct FinishView: View {
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme
    @State private var showWidgetHelp = false

    var body: some View {
        OnbScaffold {
            VStack(spacing: 4) {
                MochiPetView(vitality: 96, size: 104)
                OnbHeading(
                    eyebrow: "You're all set ✨",
                    title: "Keep Mochi where you'll see it",
                    bodyText: "A home-screen widget shows Mochi's mood and your next task at a glance — the single best way to stay on track."
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

/// The Mochi widget ships with the widget-extension milestone; until then,
/// walk the user through where widgets are added.
private struct WidgetHelpSheet: View {
    let onDone: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                MochiPetView(vitality: 90, size: 90)
                OnbHeading(
                    title: "Adding the widget",
                    bodyText: "Touch and hold your home screen, tap Edit, then Add Widget, and search for Mochi. The Mochi widget arrives with the next update — we'll nudge you when it's live."
                )
                MochiButton(title: "Got it") { onDone() }
            }
            .padding(24)
        }
    }
}
