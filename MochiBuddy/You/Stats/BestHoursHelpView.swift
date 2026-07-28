//
//  BestHoursHelpView.swift
//  MochiBuddy
//
//  The "?" screen behind the Best Hours pair - a general explainer for
//  what the charts draw, in the pet's voice. Deliberately free of the
//  user's own numbers: the cards already carry the specifics, this
//  screen teaches the shapes. Copy rules apply (no em dashes, no
//  scolding, qualitative evidence talk only).
//

import SwiftUI

struct BestHoursHelpView: View {
    let petName: String
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Reading these charts",
                    subtitle: "How \(petName) sees your hours",
                    onBack: { router.navigateBack() }
                ) {}

                bestHoursCard
                axisCard
                dayByDayCard
                whatCountsCard
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
    }

    // MARK: - Cards

    private var bestHoursCard: some View {
        helpCard("Your best hours") {
            paragraph(
                "Every finished task lands in an hour of the day. The bars stack those hours up, and the brightest three hour stretch is where the most gets done."
            )
            term("Peak", detail: "Names that stretch, as a range of hours.")
            term("In window", detail: "The share of everything you finish that lands inside it.")
        }
    }

    private var axisCard: some View {
        helpCard("The day runs 5a to 5a") {
            paragraph(
                "Both charts share one clock that starts at five in the morning. A late night counts as the end of your day, not the start of the next one, so a 2am finish sits at the far right and reads as late."
            )
        }
    }

    private var dayByDayCard: some View {
        helpCard("Day by day") {
            paragraph("Each row is one weekday, drawn from every one of those days in the window.")
            legendRow(
                swatch: AnyView(
                    Capsule().fill(theme.muted.opacity(0.45)).frame(width: 22, height: 2.5)
                ),
                title: "First to last",
                detail: "The earliest and the latest you tend to finish things on that day."
            )
            legendRow(
                swatch: AnyView(
                    Capsule().fill(theme.primarySoft).frame(width: 22, height: 12)
                ),
                title: "Middle half",
                detail: "Where the middle half of that day's completions lands. Short and bright reads as a steady routine."
            )
            legendRow(
                swatch: AnyView(
                    Circle().fill(theme.primary).frame(width: 12, height: 12)
                ),
                title: "Typical",
                detail: "The center of that day's completions, and the time shown on the right."
            )
            legendRow(
                swatch: AnyView(
                    Circle().fill(theme.muted.opacity(0.75)).frame(width: 5, height: 5)
                ),
                title: "Still learning",
                detail: "A quiet day keeps a small dot at its typical time until there is enough history to draw a shape."
            )
            paragraph(
                "The faint vertical lines mark noon and 6p, so a row can be read against the clock without a full grid. Tap a row, or use the day picker, to see one day's own hours."
            )
        }
    }

    private var whatCountsCard: some View {
        helpCard("What counts") {
            paragraph(
                "Repeating tasks sit these charts out. A standing chore would own the peak forever, so only one-off completions shape it."
            )
            paragraph(
                "\(petName) waits for enough history before drawing a shape for a day, and quiet days fill in as you go. Every time is kept in the time zone where the task was finished, so travel never rewrites your history."
            )
        }
    }

    // MARK: - Pieces

    private func helpCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        MochiCard(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)) {
            VStack(alignment: .leading, spacing: 11) {
                MochiEyebrow(text: title)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(MochiFont.body(12.5, weight: .bold))
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func term(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(MochiFont.display(9.5, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(theme.primaryText)
                .frame(width: 76, alignment: .leading)
            Text(detail)
                .font(MochiFont.body(12, weight: .bold))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(detail)")
    }

    private func legendRow(swatch: AnyView, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            swatch
                .frame(width: 26, height: 16, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(MochiFont.body(12, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Text(detail)
                    .font(MochiFont.body(11.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(detail)")
    }
}
