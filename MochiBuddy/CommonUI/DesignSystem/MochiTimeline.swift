//
//  MochiTimeline.swift
//  MochiBuddy
//
//  Vertical timeline treatment for task rows: a dashed rail down the left
//  with one node dot per row. Used by Home's Today section and the Tasks
//  tab's per-day Done groups. The rail hugs variable-height rows by
//  drawing per-row segments (half segments on the first/last rows).
//

import SwiftUI

struct MochiTimeline<Item: Identifiable & Equatable, RowContent: View>: View {
    let items: [Item]
    /// Maps a row to its node tone (danger/warn/primary/dimmed…).
    var dotColor: (Item) -> Color
    @ViewBuilder var row: (Item) -> RowContent

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .center, spacing: 8) {
                    rail(
                        showTop: index > 0,
                        showBottom: index < items.count - 1,
                        color: dotColor(item)
                    )
                    row(item)
                        .padding(.vertical, 3.5)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(MochiMotion.soft, value: items)
    }

    private func rail(showTop: Bool, showBottom: Bool, color: Color) -> some View {
        VStack(spacing: 3) {
            railSegment(visible: showTop)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.45), radius: 3)
            railSegment(visible: showBottom)
        }
        .frame(width: 14)
        .frame(maxHeight: .infinity)
    }

    private func railSegment(visible: Bool) -> some View {
        DashedVerticalLine()
            .stroke(
                visible ? theme.line : .clear,
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])
            )
            .frame(width: 1.5)
            .frame(maxHeight: .infinity)
    }

    private struct DashedVerticalLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
            return path
        }
    }
}

/// Day label above a timeline group — "Today", "Yesterday", "Mon 6 Jul".
struct MochiTimelineDateHeader: View {
    let text: String

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(MochiFont.body(10.5, weight: .heavy))
                .kerning(0.7)
                .foregroundStyle(theme.muted)
                .accessibilityAddTraits(.isHeader)
            MochiDashedDivider()
        }
    }
}

private struct TimelinePreviewItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let tone: Int
}

#Preview {
    VStack(spacing: 14) {
        MochiTimelineDateHeader(text: "Today")
        MochiTimeline(items: [
            TimelinePreviewItem(id: 0, title: "Water the plants", tone: 0),
            TimelinePreviewItem(id: 1, title: "Reply to Sam", tone: 1),
            TimelinePreviewItem(id: 2, title: "Stretch for 10 minutes", tone: 2),
        ]) { item in
            [Color.red, .orange, .purple][item.tone]
        } row: { item in
            TodoItemRow(title: item.title, meta: "Due today", onToggle: {})
        }
    }
    .padding()
}
