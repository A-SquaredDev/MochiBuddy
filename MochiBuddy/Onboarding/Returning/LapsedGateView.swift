//
//  LapsedGateView.swift
//  MochiBuddy
//

import SwiftUI

struct LapsedGateView: View {
    @State var viewModel: ObservableStateViewModel<
        LapsedGateBehavior.UIState,
        LapsedGateBehavior.ViewAction,
        LapsedGateBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            onBack: { router.navigateBack() },
            centered: false
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Halo(size: 128, glow: false) {
                            MochiPetView(vitality: 8, size: 104)
                                .overlay(alignment: .bottomTrailing) {
                                    Text("🔒")
                                        .font(.system(size: 20))
                                        .offset(x: 6, y: 2)
                                }
                        }
                        OnbHeading(
                            eyebrow: "Membership expired",
                            title: "Let's wake Mochi back up",
                            bodyText: "Your membership lapsed, so Mochi's dozed off. Reactivate to bring everything back to life — nothing was deleted."
                        )
                    }

                    HStack(spacing: 9) {
                        ForEach(viewModel.stats) { stat in
                            WaitingStat(stat: stat)
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(viewModel.plans) { plan in
                            PlanCard(
                                model: plan,
                                isSelected: plan.id == viewModel.selectedPlanId
                            ) {
                                viewModel.trigger(.selectPlan(plan.id))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.top, 6)
            }
        } footer: {
            MochiButton(title: "Reactivate membership", isLoading: viewModel.isWorking) {
                viewModel.trigger(.reactivateTapped)
            }
            MochiTextLink(title: "Restore a previous purchase", strong: true) {
                viewModel.trigger(.restoreTapped)
            }
        }
        .alert(
            "Membership",
            isPresented: viewModel.collectBinding(for: \.restoreMessage.isNotNil, action: .dismissRestoreMessage),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissRestoreMessage) } },
            message: { Text(viewModel.restoreMessage ?? "") }
        )
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .enterApp:
                router.finishOnboarding()
            case .showRestoreFound(let purchase):
                router.navigateToRestoreFound(purchase)
            }
        }
    }
}

private struct WaitingStat: View {
    let stat: LapsedGateBehavior.Stat

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Text(stat.icon).font(.system(size: 17))
            Text(stat.value)
                .font(MochiFont.display(17, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text(stat.label.uppercased())
                .font(MochiFont.body(9.5, weight: .heavy))
                .kerning(0.4)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 1.5))
    }
}
