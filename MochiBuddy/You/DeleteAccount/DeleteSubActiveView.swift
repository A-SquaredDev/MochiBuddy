//
//  DeleteSubActiveView.swift
//  MochiBuddy
//

import SwiftUI

struct DeleteSubActiveView: View {
    @State var viewModel: ObservableStateViewModel<
        DeleteSubActiveBehavior.UIState,
        DeleteSubActiveBehavior.ViewAction,
        DeleteSubActiveBehavior.NavigationEvent
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Delete account",
                    subtitle: "One important thing first",
                    onBack: { router.navigateBack() }
                )

                warningCard

                MochiButton(title: "Manage subscription in Settings") {
                    openURL(MochiLinks.manageSubscriptions)
                }

                acknowledgeCard

                MochiCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                    Text("\(Text("Heads up:").font(MochiFont.body(11.5, weight: .heavy)).foregroundColor(theme.ink)) Apple tracks free-trial eligibility per Apple ID. Deleting your account and signing up again won't grant a fresh 7-day trial.")
                        .font(MochiFont.body(11.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .lineSpacing(3)
                }

                VStack(spacing: 9) {
                    DangerButton(title: "Delete anyway") {
                        viewModel.trigger(.deleteAnywayTapped)
                    }
                    .disabled(!viewModel.acknowledged)
                    .opacity(viewModel.acknowledged ? 1 : 0.45)
                    MochiButton(title: "Cancel", variant: .ghost) {
                        viewModel.trigger(.cancelTapped)
                    }
                }
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .animation(MochiMotion.soft, value: viewModel.acknowledged)
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showFinalConfirm: router.navigateToDeleteConfirm()
            case .close: router.exitDeleteFlow()
            }
        }
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("⚠️")
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 4) {
                Text("Your subscription keeps billing")
                    .font(MochiFont.display(14.5, weight: .semibold))
                    .foregroundStyle(theme.warn)
                Text("Your Mochi+ membership belongs to your Apple ID, not this account — deleting your account \(Text("won't cancel it.").fontWeight(.heavy)) You'll keep being charged \(viewModel.priceLine) until you cancel with Apple.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(theme.warnSoft, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(theme.warn, lineWidth: 1.5)
        )
    }

    private var acknowledgeCard: some View {
        Button {
            Haptics.selection()
            viewModel.trigger(.toggleAcknowledged)
        } label: {
            MochiCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(theme.primaryInk)
                        .opacity(viewModel.acknowledged ? 1 : 0)
                        .frame(width: 22, height: 22)
                        .background(
                            viewModel.acknowledged ? theme.primary : theme.surface2,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.primary, lineWidth: 2)
                        )
                    Text("I understand my subscription won't be cancelled and I may still be billed.")
                        .font(MochiFont.body(12, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(viewModel.acknowledged ? [.isSelected] : [])
    }
}
