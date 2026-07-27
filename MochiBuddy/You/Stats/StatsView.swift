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

                rangeTabs

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

                if let bestHours = viewModel.bestHours {
                    bestHoursCard(bestHours)
                }

                if !viewModel.dayByDay.isEmpty {
                    dayByDayCard
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

    /// Week / Month / 3 months - scopes every card below it (the streak
    /// strip above stays a fixed 7 days).
    private var rangeTabs: some View {
        HStack(spacing: 4) {
            ForEach(StatsBehavior.TimeRange.allCases) { range in
                let isOn = range == viewModel.range
                Button {
                    Haptics.selection()
                    viewModel.trigger(.rangeChanged(range))
                } label: {
                    Text(range.rawValue)
                        .font(MochiFont.display(12.5, weight: .medium))
                        .foregroundStyle(isOn ? theme.primaryInk : theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(isOn ? theme.primary : .clear, in: Capsule())
                        .shadow(color: isOn ? .black.opacity(0.18) : .clear, radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(theme.surface2, in: Capsule())
        .overlay(Capsule().stroke(theme.line, lineWidth: 1.5))
        .animation(MochiMotion.soft, value: viewModel.range)
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
                MochiEyebrow(text: viewModel.range.windowLabel)
                Chart(viewModel.trend) { point in
                    BarMark(
                        x: .value(
                            viewModel.trendUnit == .week ? "Week" : "Day",
                            point.day,
                            unit: viewModel.trendUnit == .week ? .weekOfYear : .day
                        ),
                        y: .value("Done", point.count),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(theme.primary)
                    .cornerRadius(2.5)
                }
                .chartXAxis {
                    AxisMarks(values: trendAxisStride) { _ in
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

    private var trendAxisStride: AxisMarkValues {
        switch (viewModel.trendUnit, viewModel.range) {
        case (.week, _): .stride(by: .weekOfYear, count: 2)
        case (.day, .week): .stride(by: .day, count: 2)
        case (.day, _): .stride(by: .day, count: 7)
        }
    }

    /// The three shared axis ticks (12p / 6p / 11p), exact fractions of
    /// the 5a-to-5a span - both cards draw the same ruler.
    private static let axisTicks: [(fraction: Double, label: String)] = [
        (420.0 / 1440, "12p"), (780.0 / 1440, "6p"), (1080.0 / 1440, "11p"),
    ]

    private func axisRow() -> some View {
        GeometryReader { proxy in
            ForEach(Self.axisTicks, id: \.label) { tick in
                Text(tick.label)
                    .font(MochiFont.body(9, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .position(x: proxy.size.width * tick.fraction, y: 6)
            }
        }
        .frame(height: 12)
    }

    /// When things get done - 24 hourly bars on the 5a-to-5a axis, the
    /// best 3-hour window highlighted, with the peak/in-window tile pair.
    private func bestHoursCard(_ card: StatsBehavior.BestHoursCard) -> some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 10) {
                MochiEyebrow(text: "Your best hours · \(viewModel.range.suffix)")
                let maxCount = max(card.bars.map(\.count).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(card.bars) { bar in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bar.inPeak ? theme.primary : theme.primary.opacity(0.3))
                            .frame(height: max(3, 72 * CGFloat(bar.count) / CGFloat(maxCount)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 76, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Best hours: peak \(card.peakText), \(card.inWindowText) of tasks in that window")
                axisRow()
                HStack(spacing: 9) {
                    bestHoursTile(title: "Peak", value: card.peakText)
                    bestHoursTile(title: "In window", value: card.inWindowText)
                }
                Text(card.caption)
                    .font(MochiFont.body(10.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bestHoursTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(MochiFont.body(9, weight: .heavy))
                .foregroundStyle(theme.muted)
            Text(value)
                .font(MochiFont.display(15, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Seven weekday box plots on the same axis as the histogram: a thin
    /// first-to-last line, the middle-half capsule once a row earns it,
    /// and the typical dot. Thin rows show the dot alone - honest about
    /// "we know roughly when, not how consistently".
    private var dayByDayCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 9) {
                MochiEyebrow(text: "Day by day · \(viewModel.range.suffix)")
                ForEach(viewModel.dayByDay) { row in
                    HStack(spacing: 8) {
                        Text(row.label)
                            .font(MochiFont.body(11, weight: .heavy))
                            .foregroundStyle(theme.ink)
                            .frame(width: 34, alignment: .leading)
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            ZStack(alignment: .leading) {
                                if let first = row.first, let last = row.last {
                                    Capsule()
                                        .fill(theme.line)
                                        .frame(width: max(2, width * (last - first)), height: 2)
                                        .offset(x: width * first)
                                }
                                if let q1 = row.q1, let q3 = row.q3 {
                                    Capsule()
                                        .fill(theme.primary.opacity(0.45))
                                        .frame(width: max(8, width * (q3 - q1)), height: 8)
                                        .offset(x: width * q1)
                                }
                                if let typical = row.typical {
                                    Circle()
                                        .fill(theme.primary)
                                        .frame(width: 9, height: 9)
                                        .offset(x: width * typical - 4.5)
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 14)
                        Text(row.timeText ?? "")
                            .font(MochiFont.body(10, weight: .heavy))
                            .foregroundStyle(theme.muted)
                            .frame(width: 46, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowAccessibilityLabel(row))
                }
                HStack(spacing: 8) {
                    Spacer().frame(width: 34)
                    axisRow()
                    Spacer().frame(width: 46)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Capsule().fill(theme.primary.opacity(0.45)).frame(width: 16, height: 6)
                        Text("Middle half")
                    }
                    HStack(spacing: 5) {
                        Circle().fill(theme.primary).frame(width: 7, height: 7)
                        Text("Typical")
                    }
                }
                .font(MochiFont.body(9.5, weight: .bold))
                .foregroundStyle(theme.muted)
            }
        }
    }

    private func rowAccessibilityLabel(_ row: StatsBehavior.WeekdayRowUI) -> String {
        guard let timeText = row.timeText else { return "\(row.label): still quiet" }
        return row.q1 == nil
            ? "\(row.label): typically around \(timeText), still learning"
            : "\(row.label): typically around \(timeText)"
    }

    /// Magnitude comparison - bars stay one hue; identity lives in the
    /// labeled rows (list dot + name), never in the fill alone.
    private var listBreakdownCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 10) {
                MochiEyebrow(text: "Where tasks got done · \(viewModel.range.suffix)")
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
