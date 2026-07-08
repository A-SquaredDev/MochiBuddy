//
//  StatsView.swift
//  MochiBuddy
//

import SwiftUI

struct StatsView: View {
    @State var viewModel: StateViewModel<
        StatsBehavior.UIState,
        StatsBehavior.ViewAction
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Streaks",
                    subtitle: "Your gentle momentum",
                    onBack: { router.navigateBack() }
                ) {
                    CoinPill(coins: viewModel.coins)
                }

                streakCard

                LazyVGrid(columns: columns, spacing: 9) {
                    ForEach(viewModel.tiles) { tile in
                        statTile(tile)
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
    }

    private var streakCard: some View {
        MochiCard(padding: EdgeInsets(top: 16, leading: 15, bottom: 16, trailing: 15)) {
            VStack(spacing: 2) {
                Text("🔥")
                    .font(.system(size: 40))
                Text(viewModel.streakText)
                    .font(MochiFont.display(30, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(viewModel.streakSub)
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
                HStack(spacing: 8) {
                    ForEach(viewModel.week) { day in
                        VStack(spacing: 4) {
                            Text(day.count > 0 ? "\(day.count)" : "")
                                .font(MochiFont.display(11, weight: .semibold))
                                .foregroundStyle(day.level >= 3 ? theme.primaryInk : theme.muted)
                                .frame(width: 26, height: 26)
                                .background(heat(day.level), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(theme.line, lineWidth: 1.5)
                                )
                            Text(day.dayLetter)
                                .font(MochiFont.body(10, weight: .heavy))
                                .foregroundStyle(theme.muted)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.dayLetter): \(day.count) tasks done")
                    }
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statTile(_ tile: StatsBehavior.StatTile) -> some View {
        MochiCard(padding: EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.value)
                    .font(MochiFont.display(24, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(tile.title)
                    .font(MochiFont.body(11.5, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Text(tile.subtitle)
                    .font(MochiFont.body(10.5, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private func heat(_ level: Int) -> Color {
        switch level {
        case 0: theme.surface2
        case 1: theme.primary.opacity(0.3)
        case 2: theme.primary.opacity(0.6)
        default: theme.primary
        }
    }
}
