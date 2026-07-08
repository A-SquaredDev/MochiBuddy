//
//  RestoreSuccessView.swift
//  MochiBuddy
//
//  R3 · Membership restored — everything's unlocked, straight into the app.
//  Static screen: navigation goes directly through the Router.
//

import SwiftUI

struct RestoreSuccessView: View {
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold {
            Halo(size: 220) {
                MochiPetView(vitality: 99, size: 168)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.primaryInk)
                            .frame(width: 40, height: 40)
                            .background(theme.primary, in: Circle())
                            .shadow(color: .black.opacity(0.26), radius: 11, y: 10)
                            .offset(x: 4, y: -6)
                    }
            }
            OnbHeading(
                eyebrow: "Membership restored ✨",
                title: "You're all set — welcome home",
                bodyText: "Everything's unlocked and Mochi's beaming again. Let's get back to it."
            )
            VitalityMeter(value: 99, label: "Vitality")
                .padding(.horizontal, 6)
                .onLoad { Haptics.success() }
        } footer: {
            MochiButton(title: "Enter Mochi →") {
                router.finishOnboarding()
            }
        }
    }
}
