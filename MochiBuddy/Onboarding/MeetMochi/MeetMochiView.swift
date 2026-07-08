//
//  MeetMochiView.swift
//  MochiBuddy
//

import SwiftUI

struct MeetMochiView: View {
    @State var viewModel: ObservableStateViewModel<
        MeetMochiBehavior.UIState,
        MeetMochiBehavior.ViewAction,
        MeetMochiBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    private var backAction: (() -> Void)? {
        guard viewModel.canGoBack else { return nil }
        return { viewModel.trigger(.backTapped) }
    }

    var body: some View {
        OnbScaffold(
            progress: (index: 0, total: 8),
            onBack: backAction
        ) {
            Halo(size: 230, glow: viewModel.page.glow) {
                MochiPetView(vitality: viewModel.page.vitality, size: 168, squishOnTap: true)
                    .overlay(alignment: .topTrailing) {
                        if viewModel.page.showsCoinBadge {
                            Text("+5 ¢ · nice one")
                                .font(MochiFont.display(12, weight: .semibold))
                                .foregroundStyle(theme.primaryInk)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(theme.primary, in: Capsule())
                                .shadow(color: .black.opacity(0.24), radius: 9, y: 8)
                                .offset(x: 24, y: -2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            OnbHeading(
                eyebrow: viewModel.page.eyebrow,
                title: viewModel.page.title,
                bodyText: viewModel.page.body
            )
            if let meterValue = viewModel.page.meterValue {
                VitalityMeter(value: meterValue, label: "Vitality")
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
        } footer: {
            MochiButton(title: viewModel.page.cta) {
                viewModel.trigger(.continueTapped)
            }
        }
        .animation(MochiMotion.mood, value: viewModel.pageIndex)
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showFirstTask:
                router.navigateToFirstTask()
            }
        }
    }
}
