//
//  RestoreFoundView.swift
//  MochiBuddy
//

import SwiftUI

struct RestoreFoundView: View {
    @State var viewModel: ObservableStateViewModel<
        RestoreFoundBehavior.UIState,
        RestoreFoundBehavior.ViewAction,
        RestoreFoundBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            onBack: { router.navigateBack() }
        ) {
            Halo(size: 172) {
                MochiPetView(vitality: 70, size: 128)
            }
            OnbHeading(
                eyebrow: "Good news",
                title: "We found your membership",
                bodyText: "There's an active Mochi membership on this Apple ID. Restore it and you're right back in — no charge."
            )
            membershipCard
                .padding(.horizontal, 2)
        } footer: {
            MochiButton(title: "Restore & continue", isLoading: viewModel.isWorking) {
                viewModel.trigger(.restoreTapped)
            }
            MochiTextLink(title: "Use a different Apple ID") {
                viewModel.trigger(.differentAppleIdTapped)
            }
        }
        .alert(
            "Switching Apple ID",
            isPresented: viewModel.collectBinding(for: \.showAppleIdNote, action: .dismissAppleIdNote),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissAppleIdNote) } },
            message: { Text("Purchases follow the Apple ID signed into this device. Switch accounts in Settings → App Store, then come back.") }
        )
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showSuccess:
                router.navigateToRestoreSuccess()
            }
        }
    }

    private var membershipCard: some View {
        HStack(spacing: 11) {
            Text("🍡")
                .font(.system(size: 17))
                .frame(width: 34, height: 34)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.planLine)
                    .font(MochiFont.display(13.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(viewModel.renewsLine)
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.primaryText)
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.primary, lineWidth: 2)
        )
    }
}
