//
//  WidgetHelpSheet.swift
//  MochiBuddy
//
//  The add-the-widget walkthrough, shared by the onboarding Finish screen
//  and the Home setup nudge.
//

import SwiftUI

struct WidgetHelpSheet: View {
    let onDone: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                MochiPetView(vitality: 90, size: 90)
                OnbHeading(
                    title: "Adding the widget",
                    bodyText: "Touch and hold your home screen, tap Edit, then Add Widget, and search for Mochi. Pick the size you like - the medium one shows your next tasks."
                )
                MochiButton(title: "Got it") { onDone() }
            }
            .padding(24)
        }
    }
}
