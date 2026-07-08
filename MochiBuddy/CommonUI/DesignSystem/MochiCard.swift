//
//  MochiCard.swift
//  MochiBuddy
//
//  The design system's Card — soft surface panel with a hairline border.
//  Plus the small uppercase section label ("eyebrow") used between groups.
//

import SwiftUI

struct MochiCard<Content: View>: View {
    var padding = EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)
    @ViewBuilder let content: Content

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(theme.line, lineWidth: 1.5)
            )
    }
}

/// Soft dashed separator between rows inside a card.
struct MochiDashedDivider: View {
    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Line()
            .stroke(theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .frame(height: 1.5)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }
    }
}

/// Small uppercase section label — "FLAVOR", "ACCOUNT", "ABOUT & LEGAL".
struct MochiEyebrow: View {
    let text: String

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(MochiFont.body(10.5, weight: .heavy))
            .kerning(0.7)
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
