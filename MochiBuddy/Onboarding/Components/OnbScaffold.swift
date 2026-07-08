//
//  OnbScaffold.swift
//  MochiBuddy
//
//  The onboarding phone frame: optional back chevron + segmented progress +
//  skip on top, a flexible body, and a pinned footer for the primary CTA.
//

import SwiftUI

struct OnbScaffold<Content: View, Footer: View>: View {
    private let progress: (index: Int, total: Int)?
    private let onBack: (() -> Void)?
    private let skipTitle: String?
    private let onSkip: (() -> Void)?
    private let centered: Bool
    private let content: Content
    private let footer: Footer

    @Environment(\.mochiTheme) private var theme

    init(
        progress: (index: Int, total: Int)? = nil,
        onBack: (() -> Void)? = nil,
        skipTitle: String? = nil,
        onSkip: (() -> Void)? = nil,
        centered: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.progress = progress
        self.onBack = onBack
        self.skipTitle = skipTitle
        self.onSkip = onSkip
        self.centered = centered
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topRow
                VStack(spacing: 16) {
                    if centered { Spacer(minLength: 0) }
                    content
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    footer
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var topRow: some View {
        if progress != nil || onBack != nil || skipTitle != nil {
            HStack(spacing: 12) {
                if let onBack {
                    OnbBackButton(action: onBack)
                }
                if let progress {
                    SegmentedProgressBar(index: progress.index, total: progress.total)
                }
                if let skipTitle {
                    Button(action: { onSkip?() }) {
                        Text(skipTitle)
                            .font(MochiFont.body(12, weight: .heavy))
                            .foregroundStyle(theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .frame(height: 34)
        }
    }
}

struct OnbBackButton: View {
    let action: () -> Void
    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.ink)
                .frame(width: 30, height: 30)
                .background(theme.surface2, in: Circle())
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("Back")
    }
}

/// Eyebrow · headline · body — the standard onboarding heading block.
struct OnbHeading: View {
    var eyebrow: String?
    let title: String
    var bodyText: String?
    var align: HorizontalAlignment = .center

    @Environment(\.mochiTheme) private var theme

    private var textAlign: TextAlignment {
        align == .leading ? .leading : .center
    }

    var body: some View {
        VStack(alignment: align, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(MochiFont.body(10.5, weight: .heavy))
                    .kerning(0.7)
                    .foregroundStyle(theme.primaryText)
            }
            Text(title)
                .font(MochiFont.display(25, weight: .semibold))
                .lineSpacing(2)
                .foregroundStyle(theme.ink)
            if let bodyText {
                Text(bodyText)
                    .font(MochiFont.body(13.5, weight: .bold))
                    .lineSpacing(4)
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: 300, alignment: align == .leading ? .leading : .center)
            }
        }
        .multilineTextAlignment(textAlign)
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .center)
    }
}

/// Soft radial glow behind the pet / illustrative glyphs.
struct Halo<Content: View>: View {
    private let size: CGFloat
    private let glow: Bool
    private let content: Content

    @Environment(\.mochiTheme) private var theme

    init(size: CGFloat = 220, glow: Bool = true, @ViewBuilder content: () -> Content) {
        self.size = size
        self.glow = glow
        self.content = content()
    }

    var body: some View {
        ZStack {
            if glow {
                RadialGradient(
                    colors: [theme.primarySoft, .clear],
                    center: UnitPoint(x: 0.5, y: 0.45),
                    startRadius: 0,
                    endRadius: size * 0.55
                )
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
            content
        }
        .frame(height: size)
    }
}
