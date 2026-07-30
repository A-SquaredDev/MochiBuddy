//
//  JournalView.swift
//  MochiBuddy
//
//  The Journal tab, per the Feature 6 design (Journal Tab.dc.html):
//  possessive live header, hero unread letter, month-grouped story
//  timeline on a dot rail, the "{name} has noticed" card, and the record
//  footer. Lapsed renders everything desaturated and frozen with zero
//  come-back copy. Absent sections are omitted, never placeholdered.
//

import SwiftUI
import Charts

struct JournalView: View {
    @State var viewModel: JournalViewModel
    let router: any JournalRouting
    let coordinator: TabCoordinator?

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header

                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                } else if let young = viewModel.young {
                    youngState(young)
                } else {
                    content
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onAppear { viewModel.trigger(.load) }
        .onChange(of: coordinator?.pendingLetterRoute) { _, route in
            if route != nil {
                viewModel.trigger(.consumePendingRoute)
            }
        }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .openLetter(let letter, let source):
                router.navigateToLetter(letter, source: source)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MochiEyebrow(text: "Journal")
                Text(String(format: "%@'s Journal", viewModel.petName))
                    .font(MochiFont.display(27, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = viewModel.headerSubtitle {
                    Text(subtitle)
                        .font(MochiFont.body(12, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.isLapsed {
                MochiPetView(mood: .sleeping, size: 56, squishOnTap: false)
                    .opacity(0.8)
                    .saturation(0.6)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Young (day one)

    private func youngState(_ young: JournalBehavior.YoungState) -> some View {
        VStack(spacing: 8) {
            MochiPetView(mood: .content, size: 120, squishOnTap: false)
                .padding(.top, 28)
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("Day one")
                    .textCase(.uppercase)
                    .kerning(1.3)
            }
            .font(MochiFont.body(11, weight: .heavy))
            .foregroundStyle(theme.primaryText)
            .padding(.top, 4)
            Text(young.adoptionText)
                .font(MochiFont.display(20, weight: .semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Text(young.dateLabel)
                .font(MochiFont.body(12, weight: .heavy))
                .foregroundStyle(theme.muted)
            MochiDashedDivider()
                .frame(width: 150)
                .padding(.vertical, 16)
            // Accurate to Feature 3's gating: a day-one user does not get
            // the upcoming Sunday's letter.
            Text("After your first full week together, Sunday letters will collect here.")
                .font(MochiFont.body(13, weight: .bold))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Grown content

    @ViewBuilder
    private var content: some View {
        Group {
            if let hero = viewModel.hero {
                heroCard(hero)
            }

            timeline
                .onScrollVisibilityChange(threshold: 0.5) { visible in
                    if visible { viewModel.trigger(.sectionVisible(.timeline)) }
                }

            if !viewModel.noticedLines.isEmpty {
                noticedCard
                    .onScrollVisibilityChange(threshold: 0.5) { visible in
                        if visible { viewModel.trigger(.sectionVisible(.observations)) }
                    }
            }

            if let footer = viewModel.footer {
                footerCard(footer)
                    .onScrollVisibilityChange(threshold: 0.5) { visible in
                        if visible { viewModel.trigger(.sectionVisible(.data)) }
                    }
            }
        }
        .saturation(viewModel.isLapsed ? 0.72 : 1)
    }

    private func heroCard(_ hero: JournalBehavior.HeroLetter) -> some View {
        Button {
            viewModel.trigger(.heroTapped)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(theme.accent2)
                        .frame(width: 8, height: 8)
                    Text("New letter · this week")
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .font(MochiFont.body(10, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                }
                Text("\u{201C}\(hero.excerpt)\u{201D}")
                    .font(MochiFont.display(16, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack {
                    Text("From \(viewModel.petName)")
                        .font(MochiFont.display(12, weight: .medium))
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Text("Read letter")
                        .font(MochiFont.display(13, weight: .semibold))
                        .foregroundStyle(theme.primaryInk)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(theme.primary, in: Capsule())
                }
            }
            .padding(EdgeInsets(top: 15, leading: 15, bottom: 14, trailing: 15))
            .background(
                LinearGradient(
                    colors: [theme.primarySoft, theme.surface],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(theme.primary, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New unread letter from \(viewModel.petName). \(hero.excerpt)")
        .accessibilityHint("Opens the letter")
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.months) { month in
                HStack(spacing: 10) {
                    Text(month.title)
                        .font(MochiFont.display(13, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                }
                .padding(.vertical, 10)

                ForEach(month.rows) { row in
                    timelineRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ row: JournalBehavior.TimelineRow) -> some View {
        HStack(alignment: .top, spacing: 13) {
            rail(for: row)
            switch row {
            case .letter(let letter):
                letterRow(letter)
            case .moment(let moment):
                momentRow(moment)
            }
        }
    }

    private func rail(for row: JournalBehavior.TimelineRow) -> some View {
        let filled = switch row {
        case .letter: true
        case .moment(let moment): moment.isOrigin
        }
        return VStack(spacing: 0) {
            Circle()
                .fill(filled ? theme.primary : theme.bg)
                .overlay(
                    Circle().stroke(
                        filled ? theme.primarySoft : theme.primary,
                        lineWidth: filled ? 4 : 2
                    )
                )
                .frame(width: 11, height: 11)
                .padding(.top, 10)
            Rectangle()
                .fill(theme.line)
                .frame(width: 2)
                .padding(.top, 5)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    private func letterRow(_ letter: JournalBehavior.LetterRow) -> some View {
        Button {
            viewModel.trigger(.letterTapped(letter.letterId))
        } label: {
            MochiCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: letter.isUnread ? "envelope.badge.fill" : "envelope.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Sunday letter")
                                .textCase(.uppercase)
                                .kerning(1.1)
                        }
                        .font(MochiFont.body(10, weight: .heavy))
                        .foregroundStyle(letter.isUnread ? theme.primaryText : theme.muted)
                        Spacer()
                        Text(letter.dateLabel)
                            .font(MochiFont.body(11, weight: .heavy))
                            .foregroundStyle(theme.muted)
                    }
                    Text("\u{201C}\(letter.excerpt)\u{201D}")
                        .font(MochiFont.display(14, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack {
                        Text("From \(viewModel.petName)")
                            .font(MochiFont.display(12, weight: .medium))
                            .foregroundStyle(theme.muted)
                        Spacer()
                        Text(letter.isUnread ? "Unread" : "Read")
                            .font(MochiFont.body(10, weight: .heavy))
                            .foregroundStyle(letter.isUnread ? theme.primaryInk : theme.muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                letter.isUnread ? theme.primary : theme.primarySoft,
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
        .accessibilityLabel(
            letter.isUnread
                ? "\(letter.dateLabel), unread letter. \(letter.excerpt)"
                : "\(letter.dateLabel), letter. \(letter.excerpt)"
        )
    }

    /// Noninteractive by design - tapping a moment does nothing in v1, so
    /// the row exposes no button traits.
    private func momentRow(_ moment: JournalBehavior.MomentRow) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.primarySoft)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(moment.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(theme.primaryText)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.text)
                    .font(MochiFont.body(12.5, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Text(moment.dateLabel)
                    .font(MochiFont.body(11, weight: .heavy))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moment.text)
        .accessibilityValue(moment.dateLabel)
    }

    private var noticedCard: some View {
        MochiCard(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(theme.primarySoft)
                        .frame(width: 32, height: 32)
                        .overlay(
                            MochiPetView(
                                mood: viewModel.isLapsed ? .sleeping : .content,
                                size: 26, squishOnTap: false
                            )
                        )
                        .accessibilityHidden(true)
                    Text(String(format: "%@ has noticed", viewModel.petName))
                        .font(MochiFont.display(15, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(viewModel.noticedLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(MochiFont.body(13, weight: .bold))
                            .foregroundStyle(theme.ink)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Record footer

    private func footerCard(_ footer: JournalBehavior.Footer) -> some View {
        MochiCard(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(footer.title)
                    .textCase(.uppercase)
                    .kerning(1.3)
                    .font(MochiFont.body(10, weight: .heavy))
                    .foregroundStyle(theme.muted)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 6) {
                    ForEach(footer.week) { day in
                        VStack(spacing: 6) {
                            GeometryReader { proxy in
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(theme.primary)
                                        .frame(
                                            height: day.count > 0
                                                ? max(6, proxy.size.height * CGFloat(min(day.count, 6)) / 6)
                                                : 0
                                        )
                                }
                            }
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 8))
                            Text(day.dayLetter)
                                .font(MochiFont.body(10, weight: .heavy))
                                .foregroundStyle(theme.muted)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.dayLetter): \(day.count) tasks done")
                    }
                }

                if !footer.trend.isEmpty {
                    MochiDashedDivider()
                    MochiEyebrow(text: "Last 4 weeks")
                    Chart(footer.trend) { point in
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
                    .frame(height: 110)
                }

                MochiDashedDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(footer.doneCount)")
                            .font(MochiFont.display(22, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text(footer.doneLabel)
                            .font(MochiFont.body(10, weight: .heavy))
                            .foregroundStyle(theme.muted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(footer.doneLabel): \(footer.doneCount)")
                    if let best = footer.bestStreak {
                        Spacer()
                        Rectangle()
                            .fill(theme.line)
                            .frame(width: 1, height: 34)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                Text("\(best)")
                                    .font(MochiFont.display(22, weight: .semibold))
                                    .foregroundStyle(theme.ink)
                            }
                            Text("Best streak")
                                .font(MochiFont.body(10, weight: .heavy))
                                .foregroundStyle(theme.muted)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Best streak: \(best) days")
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}
