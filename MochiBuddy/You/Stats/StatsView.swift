//
//  StatsView.swift
//  MochiBuddy
//

import SwiftUI
import Charts

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
                    title: "Streaks & stats",
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

                if !viewModel.noticedLines.isEmpty {
                    noticedCard
                }

                if !viewModel.trend.isEmpty {
                    trendCard
                }

                if !viewModel.rhythm.isEmpty {
                    rhythmCard
                }

                if !viewModel.memoryRows.isEmpty {
                    memoriesCard
                }

                if !viewModel.listBreakdown.isEmpty {
                    listBreakdownCard
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
                Image(systemName: "flame.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(theme.primaryText)
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

    /// Qualified observations in the pet's voice - attention, not
    /// measurement; the numbers live in the cards around it.
    private var noticedCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 10) {
                MochiEyebrow(text: "\(viewModel.petName) has noticed")
                ForEach(viewModel.noticedLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "eyes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .padding(.top, 2)
                        Text(line)
                            .font(MochiFont.body(12.5, weight: .bold))
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Mined memories - concrete past wins, told factually.
    private var memoriesCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 11) {
                MochiEyebrow(text: "Worth remembering")
                ForEach(viewModel.memoryRows) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(MochiFont.body(12, weight: .heavy))
                                .foregroundStyle(theme.ink)
                            Text(row.subtitle)
                                .font(MochiFont.body(11, weight: .bold))
                                .foregroundStyle(theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.title): \(row.subtitle)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Charts

    /// Single-series magnitude - one hue, no legend, weekly axis ticks.
    private var trendCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                MochiEyebrow(text: "Last 4 weeks")
                Chart(viewModel.trend) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Done", point.count),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(theme.primary)
                    .cornerRadius(2.5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine().foregroundStyle(theme.line)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(MochiFont.body(9, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(theme.line.opacity(0.6))
                        AxisValueLabel()
                            .font(MochiFont.body(9, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                }
                .frame(height: 130)
                if let caption = viewModel.trendCaption {
                    Text(caption)
                        .font(MochiFont.body(10.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }

    /// When things get done - four bands, magnitude bars, one hue.
    private var rhythmCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 10) {
                MochiEyebrow(text: "Your rhythm · 4 weeks")
                let maxCount = max(viewModel.rhythm.map(\.count).max() ?? 1, 1)
                ForEach(viewModel.rhythm) { bar in
                    HStack(spacing: 8) {
                        Text(bar.label)
                            .font(MochiFont.body(11, weight: .heavy))
                            .foregroundStyle(theme.ink)
                            .frame(width: 88, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(theme.primary.opacity(bar.count == 0 ? 0.25 : 1))
                                .frame(
                                    width: max(6, proxy.size.width * CGFloat(bar.count) / CGFloat(maxCount)),
                                    height: 8
                                )
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                        Text("\(bar.count)")
                            .font(MochiFont.body(10.5, weight: .heavy))
                            .foregroundStyle(theme.muted)
                            .frame(minWidth: 20, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bar.label): \(bar.count) tasks done")
                }
                if let caption = viewModel.rhythmCaption {
                    Text(caption)
                        .font(MochiFont.body(10.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }

    /// Magnitude comparison - bars stay one hue; identity lives in the
    /// labeled rows (list dot + name), never in the fill alone.
    private var listBreakdownCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 10) {
                MochiEyebrow(text: "Where tasks got done · 4 weeks")
                let maxCount = viewModel.listBreakdown.map(\.count).max() ?? 1
                ForEach(viewModel.listBreakdown) { slice in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        Text(slice.name)
                            .font(MochiFont.body(11, weight: .heavy))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                            .frame(width: 88, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(theme.primary)
                                .frame(
                                    width: max(6, proxy.size.width * CGFloat(slice.count) / CGFloat(maxCount)),
                                    height: 8
                                )
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                        Text("\(slice.count)")
                            .font(MochiFont.body(10.5, weight: .heavy))
                            .foregroundStyle(theme.muted)
                            .frame(minWidth: 20, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(slice.name): \(slice.count) tasks done")
                }
            }
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
