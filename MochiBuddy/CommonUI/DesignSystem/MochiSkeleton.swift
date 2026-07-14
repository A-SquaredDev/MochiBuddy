//
//  MochiSkeleton.swift
//  MochiBuddy
//
//  Loading skeletons — soft placeholder "bones" with a flavor-tinted
//  shimmer sweep, plus a snoozing Mochi that cycles playful status lines.
//  Shown while the first Firestore fetch is in flight so screens never
//  pop from empty to full.
//

import SwiftUI

/// A single placeholder blob. `width: nil` stretches to fill.
struct SkeletonBone: View {
    var width: CGFloat?
    var height: CGFloat = 12
    var radius: CGFloat = 6

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(theme.line)
            .frame(width: width, height: height)
    }
}

/// Placeholder mirroring TodoItemRow's geometry — checkbox, two text
/// lines, trailing chip. Vary the widths so a stack reads organic.
struct SkeletonTodoRow: View {
    var titleWidth: CGFloat = 150
    var metaWidth: CGFloat = 90

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.line, lineWidth: 2.5)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBone(width: titleWidth, height: 11)
                SkeletonBone(width: metaWidth, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SkeletonBone(width: 44, height: 17, radius: 9)
        }
        .padding(EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, lineWidth: 1.5)
        )
    }
}

/// Cycles short playful status lines with a soft crossfade.
struct MochiLoadingPhrase: View {
    var phrases = [
        "Fetching your day…",
        "Fluffing the pillows…",
        "Counting treats…",
        "Warming up the sun spot…",
    ]

    @Environment(\.mochiTheme) private var theme
    @State private var index = 0

    var body: some View {
        Text(phrases[index])
            .font(MochiFont.body(11, weight: .bold))
            .foregroundStyle(theme.muted)
            .id(index)
            .transition(.opacity)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.8))
                    guard !Task.isCancelled else { break }
                    withAnimation(MochiMotion.soft) {
                        index = (index + 1) % phrases.count
                    }
                }
            }
    }
}

/// Sweeps a soft highlight across the modified view, masked to its own
/// shape — apply once to a skeleton layout's root. Honors Reduce Motion
/// by leaving the bones still.
struct MochiShimmer: ViewModifier {
    @Environment(\.mochiTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let band = geo.size.width * 0.6
                        LinearGradient(
                            colors: [.clear, highlight, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: sweep ? geo.size.width : -band)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }

    private var highlight: Color {
        .white.opacity(theme.isDark ? 0.10 : 0.65)
    }
}

extension View {
    func mochiShimmer() -> some View {
        modifier(MochiShimmer())
    }
}

#Preview {
    VStack(spacing: 12) {
        MochiPetView(mood: .sleeping, size: 122, bobbing: true)
        MochiLoadingPhrase()
        SkeletonTodoRow(titleWidth: 160, metaWidth: 96)
        SkeletonTodoRow(titleWidth: 120, metaWidth: 72)
        SkeletonTodoRow(titleWidth: 180, metaWidth: 110)
    }
    .padding(18)
    .mochiShimmer()
    .background(MochiTheme.sesame.bg)
    .environment(\.mochiTheme, .sesame)
}
