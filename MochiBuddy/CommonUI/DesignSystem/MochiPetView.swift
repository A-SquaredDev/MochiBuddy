//
//  MochiPetView.swift
//  MochiBuddy
//
//  The brand's virtual pet — a soft blob whose face and saturation reflect
//  vitality. Ported from the design system's MochiPet SVG (viewBox 180×170).
//  Four moods: thriving, content, tired, unwell. Body colors come from the
//  flavor's pet tokens; sparkles use primary/accent2. Tap to squish.
//

import SwiftUI

enum MochiMood: Equatable {
    case thriving
    case content
    case tired
    case unwell

    /// Mood bands: 80+ thriving, 50+ content, 25+ tired, else unwell.
    init(vitality: Double) {
        switch vitality {
        case 80...: self = .thriving
        case 50..<80: self = .content
        case 25..<50: self = .tired
        default: self = .unwell
        }
    }

    var saturation: Double {
        switch self {
        case .thriving, .content: 1
        case .tired: 0.7
        case .unwell: 0.42
        }
    }
}

struct MochiPetView: View {
    let mood: MochiMood
    var size: CGFloat = 118
    var squishOnTap = true
    var bobbing = false

    @Environment(\.mochiTheme) private var theme
    @State private var squishTrigger = 0
    @State private var bobPhase = false

    init(vitality: Double, size: CGFloat = 118, squishOnTap: Bool = true, bobbing: Bool = false) {
        self.mood = MochiMood(vitality: vitality)
        self.size = size
        self.squishOnTap = squishOnTap
        self.bobbing = bobbing
    }

    init(mood: MochiMood, size: CGFloat = 118, squishOnTap: Bool = true, bobbing: Bool = false) {
        self.mood = mood
        self.size = size
        self.squishOnTap = squishOnTap
        self.bobbing = bobbing
    }

    private var faceInk: Color { Color(hex: 0x3A2B33) }
    private var scale: CGFloat { size / 180 }

    var body: some View {
        ZStack {
            canvasBody
            if mood == .thriving {
                SparkleView(color: theme.primary, delay: 0)
                    .frame(width: 20 * scale, height: 20 * scale)
                    .position(x: 40 * scale, y: 70 * scale)
                SparkleView(color: theme.accent2, delay: 0.4)
                    .frame(width: 16 * scale, height: 16 * scale)
                    .position(x: 140 * scale, y: 74 * scale)
            }
        }
        .frame(width: size, height: size * 170 / 180)
        .saturation(mood.saturation)
        .animation(MochiMotion.mood, value: mood)
        .keyframeAnimator(initialValue: SquishValue(), trigger: squishTrigger) { content, value in
            content.scaleEffect(x: value.x, y: value.y, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(1.12, duration: 0.15)
                CubicKeyframe(0.92, duration: 0.125)
                CubicKeyframe(1.04, duration: 0.1)
                CubicKeyframe(1.0, duration: 0.125)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(0.86, duration: 0.15)
                CubicKeyframe(1.1, duration: 0.125)
                CubicKeyframe(0.97, duration: 0.1)
                CubicKeyframe(1.0, duration: 0.125)
            }
        }
        .offset(y: bobbing && bobPhase ? -5 : 0)
        .onAppear {
            guard bobbing else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                bobPhase = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard squishOnTap else { return }
            Haptics.impact(.soft)
            squishTrigger += 1
        }
        .accessibilityLabel("Mochi, feeling \(accessibilityMood)")
    }

    private var accessibilityMood: String {
        switch mood {
        case .thriving: "great"
        case .content: "content"
        case .tired: "tired"
        case .unwell: "very sad"
        }
    }

    private var canvasBody: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 180
            ctx.scaleBy(x: s, y: s)

            // ground shadow
            ctx.fill(
                Path(ellipseIn: CGRect(x: 40, y: 141, width: 100, height: 18)),
                with: .color(.black.opacity(0.08))
            )

            // body blob
            var body = Path()
            body.move(to: p(90, 24))
            body.addCurve(to: p(28, 86), control1: p(52, 24), control2: p(28, 50))
            body.addCurve(to: p(90, 138), control1: p(28, 116), control2: p(50, 138))
            body.addCurve(to: p(152, 86), control1: p(130, 138), control2: p(152, 116))
            body.addCurve(to: p(90, 24), control1: p(152, 50), control2: p(128, 24))
            body.closeSubpath()
            ctx.fill(body, with: .color(theme.pet))

            // top highlight
            var highlight = Path()
            highlight.move(to: p(90, 24))
            highlight.addCurve(to: p(28, 86), control1: p(52, 24), control2: p(28, 50))
            highlight.addCurve(to: p(31, 102), control1: p(28, 92), control2: p(29, 97))
            highlight.addCurve(to: p(90, 52), control1: p(37, 72), control2: p(61, 52))
            highlight.addCurve(to: p(149, 102), control1: p(119, 52), control2: p(143, 72))
            highlight.addCurve(to: p(152, 86), control1: p(151, 97), control2: p(152, 92))
            highlight.addCurve(to: p(90, 24), control1: p(152, 50), control2: p(128, 24))
            highlight.closeSubpath()
            ctx.fill(highlight, with: .color(theme.pet2.opacity(0.55)))

            // cheeks
            ctx.fill(
                Path(ellipseIn: CGRect(x: 45, y: 92, width: 22, height: 16)),
                with: .color(theme.petCheek.opacity(0.55))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: 113, y: 92, width: 22, height: 16)),
                with: .color(theme.petCheek.opacity(0.55))
            )

            drawFace(&ctx)
        }
    }

    private func drawFace(_ ctx: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: 3.4, lineCap: .round)
        let thinStroke = StrokeStyle(lineWidth: 3.2, lineCap: .round)
        let ink = GraphicsContext.Shading.color(faceInk)

        switch mood {
        case .content:
            ctx.fill(Path(ellipseIn: CGRect(x: 66, y: 82, width: 12, height: 12)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 102, y: 82, width: 12, height: 12)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 72, y: 84, width: 4, height: 4)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 108, y: 84, width: 4, height: 4)), with: .color(.white))
            var smile = Path()
            smile.move(to: p(80, 104))
            smile.addCurve(to: p(100, 104), control1: p(84, 109), control2: p(96, 109))
            ctx.stroke(smile, with: ink, style: stroke)

        case .thriving:
            var leftEye = Path()
            leftEye.move(to: p(64, 90))
            leftEye.addCurve(to: p(78, 90), control1: p(67, 84), control2: p(75, 84))
            ctx.stroke(leftEye, with: ink, style: stroke)
            var rightEye = Path()
            rightEye.move(to: p(102, 90))
            rightEye.addCurve(to: p(116, 90), control1: p(105, 84), control2: p(113, 84))
            ctx.stroke(rightEye, with: ink, style: stroke)
            var grin = Path()
            grin.move(to: p(78, 102))
            grin.addCurve(to: p(102, 102), control1: p(83, 110), control2: p(97, 110))
            ctx.stroke(grin, with: ink, style: stroke)

        case .tired:
            var leftEye = Path()
            leftEye.move(to: p(66, 90))
            leftEye.addLine(to: p(78, 90))
            ctx.stroke(leftEye, with: ink, style: stroke)
            var rightEye = Path()
            rightEye.move(to: p(102, 90))
            rightEye.addLine(to: p(114, 90))
            ctx.stroke(rightEye, with: ink, style: stroke)
            var mouth = Path()
            mouth.move(to: p(82, 106))
            mouth.addCurve(to: p(96, 106), control1: p(85, 104), control2: p(93, 104))
            ctx.stroke(mouth, with: ink, style: thinStroke)
            ctx.fill(sweatDrop(at: CGPoint(x: 126, y: 78)), with: .color(Color(hex: 0x8FD3F4)))

        case .unwell:
            var leftBrow = Path()
            leftBrow.move(to: p(66, 86))
            leftBrow.addCurve(to: p(79, 86), control1: p(69, 83), control2: p(77, 83))
            ctx.stroke(leftBrow, with: ink, style: thinStroke)
            var rightBrow = Path()
            rightBrow.move(to: p(101, 86))
            rightBrow.addCurve(to: p(114, 86), control1: p(104, 83), control2: p(112, 83))
            ctx.stroke(rightBrow, with: ink, style: thinStroke)
            ctx.fill(Path(ellipseIn: CGRect(x: 67.5, y: 87.5, width: 9, height: 9)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 103.5, y: 87.5, width: 9, height: 9)), with: ink)
            var frown = Path()
            frown.move(to: p(80, 110))
            frown.addCurve(to: p(100, 110), control1: p(85, 104), control2: p(95, 104))
            ctx.stroke(frown, with: ink, style: thinStroke)
            ctx.fill(sweatDrop(at: CGPoint(x: 128, y: 80)), with: .color(Color(hex: 0x8FD3F4)))
        }
    }

    /// Teardrop: c4 6 4 11 0 11 s-4-5 0-11z from the SVG.
    private func sweatDrop(at origin: CGPoint) -> Path {
        var drop = Path()
        drop.move(to: origin)
        drop.addCurve(
            to: CGPoint(x: origin.x, y: origin.y + 11),
            control1: CGPoint(x: origin.x + 4, y: origin.y + 6),
            control2: CGPoint(x: origin.x + 4, y: origin.y + 11)
        )
        drop.addCurve(
            to: origin,
            control1: CGPoint(x: origin.x - 4, y: origin.y + 11),
            control2: CGPoint(x: origin.x - 4, y: origin.y + 6)
        )
        drop.closeSubpath()
        return drop
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct SquishValue {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

/// Four-point twinkle star, pulsing like the SVG's mochi-twinkle keyframes.
private struct SparkleView: View {
    let color: Color
    let delay: Double
    @State private var lit = false

    var body: some View {
        SparkleShape()
            .fill(color)
            .opacity(lit ? 1 : 0.3)
            .scaleEffect(lit ? 1.15 : 0.8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)) {
                    lit = true
                }
            }
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let waist = 0.3 // how pinched the star's waist is
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - ry))
        path.addLine(to: CGPoint(x: cx + rx * waist, y: cy - ry * waist))
        path.addLine(to: CGPoint(x: cx + rx, y: cy))
        path.addLine(to: CGPoint(x: cx + rx * waist, y: cy + ry * waist))
        path.addLine(to: CGPoint(x: cx, y: cy + ry))
        path.addLine(to: CGPoint(x: cx - rx * waist, y: cy + ry * waist))
        path.addLine(to: CGPoint(x: cx - rx, y: cy))
        path.addLine(to: CGPoint(x: cx - rx * waist, y: cy - ry * waist))
        path.closeSubpath()
        return path
    }
}

#Preview("Moods") {
    HStack(spacing: 12) {
        MochiPetView(mood: .thriving, size: 90)
        MochiPetView(mood: .content, size: 90)
        MochiPetView(mood: .tired, size: 90)
        MochiPetView(mood: .unwell, size: 90)
    }
    .padding()
    .background(MochiTheme.sesame.bg)
    .environment(\.mochiTheme, .sesame)
}
