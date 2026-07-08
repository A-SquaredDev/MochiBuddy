//
//  SplashView.swift
//  MochiBuddy
//
//  1 · Splash — branded, Mochi bobbing while Firebase spins up.
//

import SwiftUI
import Combine

struct SplashView: View {
    @State var viewModel: ObservableStateViewModel<
        SplashBehavior.UIState,
        SplashBehavior.ViewAction,
        SplashBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme
    @State private var activeDot = 0

    private let dotTimer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Halo(size: 220) {
                    MochiPetView(vitality: 70, size: 150, squishOnTap: false, bobbing: true)
                }
                VStack(spacing: 2) {
                    Text("Mochi")
                        .font(MochiFont.display(40, weight: .semibold))
                        .kerning(-0.5)
                        .foregroundStyle(theme.ink)
                    Text("A companion for your to-dos")
                        .font(MochiFont.body(13, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
                if viewModel.failedToStart {
                    MochiButton(title: "Try again", size: .md, block: false) {
                        viewModel.trigger(.retryTapped)
                    }
                    .padding(.top, 6)
                } else {
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { dot in
                            Circle()
                                .fill(dot == activeDot ? theme.primary : theme.surface2)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.top, 6)
                    .onReceive(dotTimer) { _ in
                        withAnimation(MochiMotion.soft) { activeDot = (activeDot + 1) % 3 }
                    }
                }
            }
        }
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showMeetMochi:
                router.navigateToMeetMochi()
            case .showWelcomeBack(let summary):
                router.navigateToWelcomeBack(summary)
            case .enterApp:
                router.finishOnboarding()
            }
        }
    }
}
