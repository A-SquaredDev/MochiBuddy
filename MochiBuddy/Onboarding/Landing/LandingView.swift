//
//  LandingView.swift
//  MochiBuddy
//
//  0 · Landing - the first choice screen. New users start the flow;
//  returning users jump straight to sign-in instead of walking the whole
//  wizard to find out their account still exists. Static screen:
//  navigation goes straight through the Router.
//

import SwiftUI

struct LandingView: View {
    let router: any OnboardingRouting

    var body: some View {
        OnbScaffold {
            Halo(size: 220) {
                MochiPetView(vitality: 80, size: 150, bobbing: true)
            }
            OnbHeading(
                eyebrow: "Welcome",
                title: "Meet Mochi",
                bodyText: "A tiny companion who cheers you on while you get things done."
            )
        } footer: {
            MochiButton(title: "Let's get started") {
                router.navigateToMeetMochi()
            }
            MochiTextLink(title: "I already have an account · Sign in", strong: true) {
                router.navigateToSignIn()
            }
        }
    }
}
