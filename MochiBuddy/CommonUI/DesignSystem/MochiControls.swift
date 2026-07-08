//
//  MochiControls.swift
//  MochiBuddy
//
//  Small shared controls: the pill toggle and the segmented onboarding
//  progress bar.
//

import SwiftUI

/// Pill switch with a springy knob; track fills with the flavor primary when on.
struct MochiToggle: View {
    @Binding var isOn: Bool
    var isDisabled = false

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(MochiMotion.bounce) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? theme.primary : theme.line)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .padding(3)
            }
            .frame(width: 48, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// Segmented progress across onboarding steps — the active segment stretches.
/// On appear it animates from the previous step, so each pushed screen shows
/// the bar springing forward instead of loading pre-filled.
struct SegmentedProgressBar: View {
    let index: Int
    let total: Int
    var animatesIn = true

    @State private var hasAnimatedIn = false
    @Environment(\.mochiTheme) private var theme

    private let gap: CGFloat = 5
    private let activeStretch: CGFloat = 2.2

    private var shownIndex: Int {
        animatesIn && !hasAnimatedIn ? max(0, index - 1) : index
    }

    var body: some View {
        GeometryReader { geo in
            let units = CGFloat(total - 1) + activeStretch
            let unit = max(0, geo.size.width - gap * CGFloat(total - 1)) / units
            HStack(spacing: gap) {
                ForEach(0..<total, id: \.self) { step in
                    let done = step < shownIndex
                    let active = step == shownIndex
                    Capsule()
                        .fill(done || active ? theme.primary : theme.surface2)
                        .opacity(done ? 0.55 : 1)
                        .frame(width: active ? unit * activeStretch : unit, height: 4)
                }
            }
        }
        .frame(height: 4)
        .onAppear {
            guard animatesIn, !hasAnimatedIn else { return }
            withAnimation(MochiMotion.bounce.delay(0.25)) { hasAnimatedIn = true }
        }
        .animation(MochiMotion.bounce, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(total)")
    }
}
