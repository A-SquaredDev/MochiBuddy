//
//  MoodMeter.swift
//  MochiBuddy
//
//  The two-layer mood bar — this visual IS the core mechanic. A solid
//  gradient for the baseline (only tasks move it) and a translucent striped
//  segment butted flush against it for the comfort buffer, with a "boost
//  fading" hint. A single combined bar would teach users that petting
//  permanently fixes things — it doesn't.
//

import SwiftUI

struct MoodMeter: View {
    /// Baseline mood 0–100 (earned by tasks).
    let baseline: Double
    /// Comfort buffer 0–30 (pets/treats, temporary).
    var buffer: Double = 0
    var label: String? = "Mood"
    var showsFadingHint = true
    var height: CGFloat = 12

    @Environment(\.mochiTheme) private var theme

    private var base: Double { min(100, max(0, baseline)) }
    private var bufferWidth: Double {
        min(100 - base, max(0, min(MoodEngine.Constants.bufferCap, buffer)))
    }

    var body: some View {
        VStack(spacing: 6) {
            if label != nil || (buffer > 0 && showsFadingHint) {
                HStack(alignment: .firstTextBaseline) {
                    if let label {
                        Text(label)
                            .font(MochiFont.display(11, weight: .medium))
                            .foregroundStyle(theme.ink)
                    }
                    Spacer()
                    if buffer > 0, showsFadingHint {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.primary.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(theme.primary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                )
                            Text("boost fading")
                                .font(MochiFont.body(9.5, weight: .heavy))
                                .kerning(0.3)
                                .foregroundStyle(theme.primaryText)
                        }
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.primarySoft)
                    // baseline — solid; only tasks move it. Flat edges: the
                    // outer capsule clip rounds the bar ends, so the buffer
                    // stripes butt flush against it with no seam.
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [theme.accent2, theme.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * base / 100)
                    // buffer — translucent stripes stacked on the baseline
                    if bufferWidth > 0 {
                        let bufferPixels = geo.size.width * bufferWidth / 100
                        StripedFill(color: theme.primary)
                            .frame(width: bufferPixels)
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: 0, bottomLeadingRadius: 0,
                                bottomTrailingRadius: height / 2, topTrailingRadius: height / 2
                            ))
                            .offset(x: geo.size.width * base / 100)
                    }
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
            .animation(MochiMotion.bounce, value: base)
            .animation(MochiMotion.soft, value: bufferWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Mood")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        buffer > 0
            ? "\(Int(base)) percent, plus a fading comfort boost of \(Int(buffer))"
            : "\(Int(base)) percent"
    }
}

/// 45° candy stripes for the buffer segment.
private struct StripedFill: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.3)))
            let stripe: CGFloat = 5
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var band = Path()
                band.move(to: CGPoint(x: x, y: size.height))
                band.addLine(to: CGPoint(x: x + size.height, y: 0))
                band.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
                band.addLine(to: CGPoint(x: x + stripe, y: size.height))
                band.closeSubpath()
                ctx.fill(band, with: .color(color.opacity(0.35)))
                x += stripe * 2
            }
        }
    }
}
