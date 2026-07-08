//
//  PaywallView.swift
//  MochiBuddy
//

import SwiftUI

struct PaywallView: View {
    @State var viewModel: ObservableStateViewModel<
        PaywallBehavior.UIState,
        PaywallBehavior.ViewAction,
        PaywallBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            progress: (index: 7, total: 8),
            onBack: { router.navigateBack() },
            centered: false
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        MochiPetView(vitality: 98, size: 82)
                        OnbHeading(
                            eyebrow: "Membership",
                            title: "Unlock the full Mochi",
                            bodyText: "Mochi is a membership app — one plan, everything included. Try it all free for a week."
                        )
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(viewModel.hooks) { hook in
                            HookRow(hook: hook)
                        }
                    }
                    .padding(.horizontal, 2)

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
                    .padding(.top, 6)

                    HStack(spacing: 13) {
                        Text("🔔 Reminder before it ends")
                        Text("·")
                        Button("Restore") { viewModel.trigger(.restoreTapped) }
                            .buttonStyle(.plain)
                    }
                    .font(MochiFont.body(10.5, weight: .heavy))
                    .foregroundStyle(theme.muted)
                }
                .padding(.top, 6)
            }
        } footer: {
            MochiButton(
                title: viewModel.ctaTitle,
                isLoading: viewModel.isPurchasing || viewModel.isRestoring
            ) {
                viewModel.trigger(.startTrialTapped)
            }
            MochiTextLink(title: viewModel.ctaSubtitle)
        }
        .onLoad { viewModel.trigger(.load) }
        .alert(
            "Membership",
            isPresented: viewModel.collectBinding(for: \.restoreMessage.isNotNil, action: .dismissRestoreMessage),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissRestoreMessage) } },
            message: { Text(viewModel.restoreMessage ?? "") }
        )
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToFinish()
            }
        }
    }
}

private struct HookRow: View {
    let hook: PaywallBehavior.Hook

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 11) {
            Text(hook.icon)
                .font(.system(size: 15))
                .frame(width: 32, height: 32)
                .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(hook.title)
                    .font(MochiFont.display(13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(hook.sub)
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
        }
    }
}
