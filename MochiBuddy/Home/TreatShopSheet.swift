//
//  TreatShopSheet.swift
//  MochiBuddy
//
//  The treat shop — a sheet, not a tab: feeding belongs next to the pet.
//  Treats are priced by duration (the buffer caps at +30) and every treat
//  beats the free pet. Buy = give — no inventory.
//

import SwiftUI

struct TreatShopSheet: View {
    @State var viewModel: StateViewModel<
        HomeBehavior.UIState,
        HomeBehavior.ViewAction
    >

    @Environment(\.mochiTheme) private var theme

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Treats")
                    .font(MochiFont.display(18, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer()
                CoinPill(coins: viewModel.coins)
            }
            .padding(EdgeInsets(top: 22, leading: 18, bottom: 14, trailing: 18))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    bufferCard
                    petRow
                    MochiEyebrow(text: "Treats · priced by how long they last")
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(viewModel.treats) { treat in
                            treatCard(treat)
                        }
                    }
                    Text("Treats lift Mochi \(Text("now").font(MochiFont.body(11, weight: .heavy)).foregroundColor(theme.ink)) — finishing tasks is the real cure.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 24, trailing: 18))
            }
        }
        .background(theme.bg)
        .presentationDetents([.large, .fraction(0.75)])
        .presentationDragIndicator(.visible)
    }

    private var bufferCard: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            HStack(spacing: 12) {
                MochiPetView(vitality: viewModel.displayedMood, size: 54, squishOnTap: false)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Comfort buffer")
                            .font(MochiFont.display(13, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Spacer()
                        Text(viewModel.bufferLabel)
                            .font(MochiFont.body(11, weight: .heavy))
                            .foregroundStyle(theme.primaryText)
                            .contentTransition(.numericText())
                    }
                    Text("A temporary lift — it fades on its own and never moves the baseline.")
                        .font(MochiFont.body(10.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .padding(.bottom, 6)
                    MoodMeter(
                        baseline: viewModel.baseline,
                        buffer: viewModel.buffer,
                        label: nil,
                        showsFadingHint: false,
                        height: 9
                    )
                }
            }
        }
    }

    private var petRow: some View {
        HStack(spacing: 11) {
            Text(TreatCatalog.Pet.emoji)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 1) {
                Text(TreatCatalog.Pet.name)
                    .font(MochiFont.display(13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(viewModel.petActionMeta)
                    .font(MochiFont.body(10.5, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.trigger(.petTapped)
            } label: {
                Text("Free")
                    .font(MochiFont.display(12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .background(theme.primarySoft, in: Capsule())
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel("Pet Mochi, free")
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        )
    }

    private func treatCard(_ treat: HomeBehavior.TreatUIItem) -> some View {
        MochiCard(padding: EdgeInsets(top: 13, leading: 12, bottom: 12, trailing: 12)) {
            VStack(spacing: 6) {
                Text(treat.emoji)
                    .font(.system(size: 34))
                Text(treat.name)
                    .font(MochiFont.display(13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                HStack(spacing: 5) {
                    Text(treat.liftText)
                        .font(MochiFont.body(10, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                        .padding(EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7))
                        .background(theme.primarySoft, in: Capsule())
                    Text(treat.durationText)
                        .font(MochiFont.body(10, weight: .heavy))
                        .foregroundStyle(theme.muted)
                        .padding(EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7))
                        .background(theme.surface2, in: Capsule())
                        .overlay(Capsule().stroke(theme.line, lineWidth: 1))
                }
                MochiButton(
                    title: treat.costText,
                    variant: treat.canAfford ? .primary : .ghost,
                    size: .sm,
                    isDisabled: !treat.canAfford
                ) {
                    viewModel.trigger(.giveTreat(treat.id))
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
