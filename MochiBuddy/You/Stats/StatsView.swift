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

    /// The comp's shared axis geometry: labels at exact fractions of the
    /// 5a-to-5a span, "5a" pinned to both ends - both cards draw the same
    /// ruler so they stack as a matched pair.
    private static let axisTicks: [(fraction: Double, label: String)] = [
        (420.0 / 1440, "12p"), (780.0 / 1440, "6p"), (1080.0 / 1440, "11p"),
    ]

    /// Comp geometry for Day by day: weekday label / trailing time widths.
    private static let dayLabelWidth: CGFloat = 30
    private static let dayTimeWidth: CGFloat = 48

    private func axisRow() -> some View {
        ZStack {
            HStack {
                Text("5a")
                Spacer()
                Text("5a")
            }
            GeometryReader { proxy in
                ForEach(Self.axisTicks, id: \.label) { tick in
                    Text(tick.label)
                        .position(x: proxy.size.width * tick.fraction, y: 7)
                }
            }
        }
        .font(MochiFont.body(10, weight: .heavy))
        .foregroundStyle(theme.muted)
        .frame(height: 14)
    }

    /// Stacked card header: eyebrow, window label left-aligned beneath it,
    /// and the "?" into the shared chart explainer on the trailing edge.
    private func cardHeader(_ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                MochiEyebrow(text: title)
                Text(viewModel.range.windowLabel)
                    .font(MochiFont.body(10.5, weight: .heavy))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Button {
                Haptics.impact(.light)
                router.navigateToBestHoursHelp()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About these charts")
        }
    }

    private var cardDivider: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    /// The pet-and-commentary footer both cards share.
    private func mochiCaption(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MochiPetView(mood: .content, size: 32, squishOnTap: false)
            Text(text)
                .font(MochiFont.body(12.5, weight: .heavy))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// When things get done - 24 hourly bars on the 5a-to-5a axis. Peak
    /// bars carry the accent2-to-primary gradient; everything outside
    /// drops to a muted tick so the shape reads before the numbers do.
    private func bestHoursCard(_ card: StatsBehavior.BestHoursCard) -> some View {
        MochiCard(padding: EdgeInsets(top: 16, leading: 15, bottom: 18, trailing: 15)) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Your best hours")
                    .padding(.bottom, 16)
                let maxCount = max(card.bars.map(\.count).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(card.bars) { bar in
                        UnevenRoundedRectangle(
                            topLeadingRadius: bar.inPeak ? 4 : 3,
                            topTrailingRadius: bar.inPeak ? 4 : 3
                        )
                        .fill(barFill(inPeak: bar.inPeak))
                        .frame(height: max(2, 96 * CGFloat(bar.count) / CGFloat(maxCount)))
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 96, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Best hours: peak \(card.peakText), \(card.inWindowText) of tasks in that window")
                axisRow()
                    .padding(.top, 7)
                cardDivider
                    .padding(.top, 15)
                    .padding(.bottom, 13)
                mochiCaption(card.caption)
                HStack(spacing: 9) {
                    bestHoursTile(title: "Peak", value: card.peakText, valueSize: 17, valueColor: theme.ink)
                    bestHoursTile(title: "In window", value: card.inWindowText, valueSize: 19, valueColor: theme.primaryText)
                }
                .padding(.top, 14)
            }
        }
    }

    private func barFill(inPeak: Bool) -> AnyShapeStyle {
        inPeak
            ? AnyShapeStyle(LinearGradient(
                colors: [theme.accent2, theme.primary], startPoint: .top, endPoint: .bottom
              ))
            : AnyShapeStyle(theme.muted.opacity(0.28))
    }

    private func bestHoursTile(
        title: String, value: String, valueSize: CGFloat, valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(MochiFont.display(9.5, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
            Text(value)
                .font(MochiFont.display(valueSize, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 12, trailing: 13))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1))
    }

    /// Seven weekday rows on the same axis as the histogram: first-to-last
    /// line, middle-half capsule, typical dot. Thin rows keep the label,
    /// a small muted dot and the time, and drop everything else - "one
    /// point, not enough for a shape", never a row that failed to draw.
    private var dayByDayCard: some View {
        MochiCard(padding: EdgeInsets(top: 16, leading: 15, bottom: 18, trailing: 15)) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Day by day")
                    .padding(.bottom, 11)
                dayPicker
                    .padding(.bottom, 13)

                if let detail = viewModel.dayDetail {
                    dayDetailBody(detail)
                } else {
                    allDaysBody
                }

                cardDivider
                    .padding(.top, 14)
                    .padding(.bottom, 13)
                if let caption = viewModel.dayDetail?.caption ?? viewModel.dayByDayCaption {
                    mochiCaption(caption)
                }
            }
            .animation(MochiMotion.soft, value: viewModel.selectedDay)
        }
    }

    /// The comp's picker pill (turn 3) backed by a native menu - the
    /// EFFORT pill recipe. Only days that hold any data are offered.
    private var dayPicker: some View {
        Menu {
            Picker("Day", selection: viewModel.collectBinding(
                for: \.selectedDay, action: { .selectDay($0) }
            )) {
                Text("All days").tag(Int?.none)
                ForEach(viewModel.dayByDay.filter { $0.typical != nil }) { row in
                    Text(Self.pluralDayName(row.id)).tag(Int?.some(row.id))
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(viewModel.selectedDay.map(Self.pluralDayName) ?? "All days")
                    .font(MochiFont.display(12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(theme.primaryText)
            }
            .padding(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
            .background(theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(theme.line, lineWidth: 1))
        }
        .accessibilityLabel(
            "Day filter: \(viewModel.selectedDay.map(Self.pluralDayName) ?? "All days")"
        )
    }

    /// "Mondays" - the picker and caption speak the same plural currency.
    private static func pluralDayName(_ weekday: Int) -> String {
        ObservationCopy.weekdayNames.indices.contains(weekday) && weekday >= 1
            ? ObservationCopy.weekdayNames[weekday]
            : ""
    }

    /// The seven-row comparison ("All days").
    private var allDaysBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Capsule().fill(theme.primarySoft).frame(width: 19, height: 12)
                    Text("Middle half")
                }
                HStack(spacing: 6) {
                    Circle().fill(theme.primary).frame(width: 12, height: 12)
                    Text("Typical")
                }
            }
            .font(MochiFont.body(10, weight: .heavy))
            .foregroundStyle(theme.muted)
            .padding(.bottom, 12)

            VStack(spacing: 9) {
                ForEach(viewModel.dayByDay) { row in
                    dayByDayRow(row)
                }
            }
            .background {
                // Hairline gridlines at noon and 6p, spanning the rows
                // inside the track region - readable without a grid.
                GeometryReader { proxy in
                    let trackWidth = proxy.size.width
                        - Self.dayLabelWidth - Self.dayTimeWidth - 20
                    ForEach([Self.axisTicks[0], Self.axisTicks[1]], id: \.label) { tick in
                        Rectangle()
                            .fill(theme.line)
                            .frame(width: 1, height: proxy.size.height + 4)
                            .offset(
                                x: Self.dayLabelWidth + 10 + trackWidth * tick.fraction,
                                y: -2
                            )
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer().frame(width: Self.dayLabelWidth)
                axisRow()
                Spacer().frame(width: Self.dayTimeWidth)
            }
            .padding(.top, 8)
        }
    }

    /// One picked day: its own hour curve on the shared axis, plus the
    /// day-scoped tile pair once the day has earned them (comp turn 3 -
    /// "only the middle changes").
    private func dayDetailBody(_ detail: StatsBehavior.DayDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let maxCount = max(detail.bars.map(\.count).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(detail.bars) { bar in
                    UnevenRoundedRectangle(
                        topLeadingRadius: bar.inPeak ? 4 : 3,
                        topTrailingRadius: bar.inPeak ? 4 : 3
                    )
                    .fill(barFill(inPeak: bar.inPeak))
                    .frame(height: max(2, 96 * CGFloat(bar.count) / CGFloat(maxCount)))
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayDetailAccessibilityLabel(detail))
            axisRow()
                .padding(.top, 6)
            if let peakText = detail.peakText, let inWindowText = detail.inWindowText {
                HStack(spacing: 8) {
                    bestHoursTile(title: "Peak", value: peakText, valueSize: 15, valueColor: theme.ink)
                    bestHoursTile(title: "In window", value: inWindowText, valueSize: 15, valueColor: theme.primaryText)
                }
                .padding(.top, 14)
            }
        }
    }

    private func dayDetailAccessibilityLabel(_ detail: StatsBehavior.DayDetail) -> String {
        guard let peakText = detail.peakText, let inWindowText = detail.inWindowText else {
            return "\(Self.pluralDayName(detail.weekday)): still learning"
        }
        return "\(Self.pluralDayName(detail.weekday)): peak \(peakText), \(inWindowText) of tasks in that window"
    }

    /// Rows are the second way into the day view (comp turn 3 note) -
    /// tappable whenever they hold any data.
    private func dayByDayRow(_ row: StatsBehavior.WeekdayRowUI) -> some View {
        // A row with a typical dot but no capsule is THIN: shrunken muted
        // dot, dimmed label and time.
        let isThin = row.q1 == nil
        return Button {
            guard row.typical != nil else { return }
            Haptics.selection()
            viewModel.trigger(.selectDay(row.id))
        } label: {
            dayByDayRowContent(row, isThin: isThin)
        }
        .buttonStyle(.plain)
        .disabled(row.typical == nil)
        .accessibilityLabel(rowAccessibilityLabel(row))
        .accessibilityHint(row.typical != nil ? "Shows this day's hours" : "")
    }

    private func dayByDayRowContent(
        _ row: StatsBehavior.WeekdayRowUI, isThin: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Text(row.label)
                .font(MochiFont.body(11, weight: .heavy))
                .foregroundStyle(theme.muted)
                .opacity(isThin ? 0.65 : 1)
                .frame(width: Self.dayLabelWidth, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    if let first = row.first, let last = row.last {
                        Capsule()
                            .fill(theme.muted.opacity(0.45))
                            .frame(width: max(2.5, width * (last - first)), height: 2.5)
                            .offset(x: width * first)
                    }
                    if let q1 = row.q1, let q3 = row.q3 {
                        Capsule()
                            .fill(theme.primarySoft)
                            .frame(width: max(12, width * (q3 - q1)), height: 12)
                            .offset(x: width * q1)
                    }
                    if let typical = row.typical {
                        Circle()
                            .fill(isThin ? theme.muted.opacity(0.75) : theme.primary)
                            .frame(width: isThin ? 5 : 12, height: isThin ? 5 : 12)
                            .offset(x: width * typical - (isThin ? 2.5 : 6))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)
            Text(row.timeText ?? "")
                .font(MochiFont.display(11.5, weight: .semibold))
                .foregroundStyle(isThin ? theme.muted : theme.ink)
                .frame(width: Self.dayTimeWidth, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
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
