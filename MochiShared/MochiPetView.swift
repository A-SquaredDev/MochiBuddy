//
//  MochiPetView.swift
//  MochiBuddy
//
//  The brand's virtual pet - a soft blob whose face and saturation reflect
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
    /// Bedtime - closed eyes and drifting z's; hosts set this explicitly
    /// (it never comes from vitality).
    case sleeping

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
        case .sleeping: 0.85
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
    /// Runs the mood's scripted design idle. Opt-in so the ~40 static/list
    /// instances (and icon exports) keep their cheap first-frame render;
    /// hosts turn it on for the focal pet (Home hero) where the life is
    /// worth the per-frame cost.
    var alive = false
    /// Off for static exports (IconExportTests) - the twinkle animation's
    /// first frame renders sparkles washed out.
    var showsSparkles = true
    /// Bump this to squish from outside (e.g. a "Pet Mochi" button).
    var externalSquishTrigger = 0
    /// Fires on tap regardless of squishOnTap - hosts hook petting here.
    var onTap: (() -> Void)?
    /// VoiceOver always gets the full chosen name, whatever compact
    /// chrome had to do (Personal Layer, Feature 1).
    var petName = "Mochi"

    @Environment(\.mochiTheme) private var theme
    @State private var squishTrigger = 0
    @State private var bobPhase = false
    /// True for ~1.3s after a pet - lifts a sad face, blooms color, floats
    /// hearts. Purely local comfort; never touches baseline mood or copy.
    @State private var petComfort = false

    init(
        vitality: Double,
        size: CGFloat = 118,
        squishOnTap: Bool = true,
        bobbing: Bool = false,
        alive: Bool = false,
        showsSparkles: Bool = true,
        externalSquishTrigger: Int = 0,
        onTap: (() -> Void)? = nil,
        petName: String = "Mochi"
    ) {
        self.init(
            mood: MochiMood(vitality: vitality),
            size: size,
            squishOnTap: squishOnTap,
            bobbing: bobbing,
            alive: alive,
            showsSparkles: showsSparkles,
            externalSquishTrigger: externalSquishTrigger,
            onTap: onTap,
            petName: petName
        )
    }

    init(
        mood: MochiMood,
        size: CGFloat = 118,
        squishOnTap: Bool = true,
        bobbing: Bool = false,
        alive: Bool = false,
        showsSparkles: Bool = true,
        externalSquishTrigger: Int = 0,
        onTap: (() -> Void)? = nil,
        petName: String = "Mochi"
    ) {
        self.mood = mood
        self.size = size
        self.squishOnTap = squishOnTap
        self.bobbing = bobbing
        self.alive = alive
        self.showsSparkles = showsSparkles
        self.externalSquishTrigger = externalSquishTrigger
        self.onTap = onTap
        self.petName = petName
    }

    private var faceInk: Color { Color(hex: 0x3A2B33) }
    private var scale: CGFloat { size / 180 }

    /// Combined tap + external-button pet trigger; drives hearts and comfort.
    private var petKey: Int { squishTrigger &+ externalSquishTrigger }

    /// Which scripted design idle an alive Mochi runs - one canvas per mood
    /// (MochiScriptedIdle.swift).
    private enum IdleCanvas { case thriving, content, tired, unwell, sleeping }
    private var idleCanvas: IdleCanvas? {
        guard alive else { return nil }
        switch mood {
        case .thriving: return .thriving
        case .content: return .content
        // Comfort briefly lifts a petted tired or unwell Mochi to the
        // content idle.
        case .tired: return petComfort ? .content : .tired
        case .unwell: return petComfort ? .content : .unwell
        case .sleeping: return .sleeping
        }
    }

    /// The face to draw. While comforting a sad Mochi, he softens to `content`
    /// - the visible "that feels nice" lift when you pet him.
    private var displayMood: MochiMood {
        guard petComfort else { return mood }
        switch mood {
        case .tired, .unwell: return .content
        default: return mood
        }
    }

    /// Comfort briefly restores color to a dimmed Mochi, so petting a sad pet
    /// visibly makes him bloom.
    private var effectiveSaturation: Double {
        petComfort ? max(mood.saturation, 0.92) : mood.saturation
    }

    /// Squish energy scales with how he feels: a thriving pet bounces hard, an
    /// unwell one gives a gentle, grateful squish.
    private var squishPeak: (x: CGFloat, y: CGFloat) {
        switch mood {
        case .thriving: (1.14, 0.84)
        case .content: (1.12, 0.86)
        case .tired: (1.07, 0.93)
        case .unwell: (1.06, 0.94)
        case .sleeping: (1.05, 0.95)
        }
    }

    var body: some View {
        ZStack {
            // A scripted idle owns its own motion, so the continuous
            // micro-life modifiers below stay off for it (continuousLifeActive).
            switch idleCanvas {
            case .thriving:
                ThrivingIdleCanvas(theme: theme, size: size, faceInk: faceInk, showsSparkles: showsSparkles)
            case .content:
                ContentIdleCanvas(theme: theme, size: size, faceInk: faceInk)
            case .tired:
                TiredIdleCanvas(theme: theme, size: size, faceInk: faceInk)
            case .unwell:
                UnwellIdleCanvas(theme: theme, size: size, faceInk: faceInk)
            case .sleeping:
                SleepIdleCanvas(theme: theme, size: size, faceInk: faceInk)
            case nil:
                canvasBody
                if mood == .thriving, showsSparkles {
                    SparkleView(color: theme.primary, delay: 0)
                        .frame(width: 20 * scale, height: 20 * scale)
                        .position(x: 40 * scale, y: 70 * scale)
                    SparkleView(color: theme.accent2, delay: 0.4)
                        .frame(width: 16 * scale, height: 16 * scale)
                        .position(x: 140 * scale, y: 74 * scale)
                }
                if mood == .sleeping {
                    SleepZzzView(ink: faceInk, scale: scale)
                        .position(x: 138 * scale, y: 42 * scale)
                }
            }
            // A puff of hearts rises each time he's petted.
            HeartFloatView(color: theme.primary, scale: scale, trigger: petKey)
                .position(x: 90 * scale, y: 40 * scale)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size * 170 / 180)
        .saturation(effectiveSaturation)
        .animation(MochiMotion.mood, value: mood)
        .animation(.easeInOut(duration: 0.45), value: petComfort)
        .keyframeAnimator(initialValue: SquishValue(), trigger: petKey) { content, value in
            content.scaleEffect(x: value.x, y: value.y, anchor: .bottom)
        } keyframes: { _ in
            let peak = squishPeak
            let xUnder = 1 - (peak.x - 1)
            let xSettle = 1 + (peak.x - 1) * 0.3
            let yUnder = 1 - (peak.y - 1)
            let ySettle = 1 + (peak.y - 1) * 0.3
            KeyframeTrack(\.x) {
                CubicKeyframe(peak.x, duration: 0.15)
                CubicKeyframe(xUnder, duration: 0.125)
                CubicKeyframe(xSettle, duration: 0.1)
                CubicKeyframe(1.0, duration: 0.125)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(peak.y, duration: 0.15)
                CubicKeyframe(yUnder, duration: 0.125)
                CubicKeyframe(ySettle, duration: 0.1)
                CubicKeyframe(1.0, duration: 0.125)
            }
        }
        .offset(y: bobbing && bobPhase ? -5 : 0)
        .onAppear {
            if bobbing {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    bobPhase = true
                }
            }
        }
        .task(id: petKey) { await runPetComfort() }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
            guard squishOnTap else { return }
            Haptics.impact(.soft)
            squishTrigger += 1
        }
        .accessibilityLabel("\(petName), feeling \(accessibilityMood)")
    }

    /// Holds the comfort lift for ~1.3s after a pet. Rapid petting cancels and
    /// restarts this (via `.task(id: petKey)`), so the glow stays up while
    /// you keep petting.
    private func runPetComfort() async {
        guard petKey != 0 else { return }
        petComfort = true
        try? await Task.sleep(for: .seconds(1.3))
        guard !Task.isCancelled else { return }
        petComfort = false
    }

    private var accessibilityMood: String {
        switch mood {
        case .thriving: "great"
        case .content: "content"
        case .tired: "tired"
        case .unwell: "very sad"
        case .sleeping: "asleep"
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

            drawFace(&ctx, mood: displayMood)
        }
    }

    private func drawFace(_ ctx: inout GraphicsContext, mood: MochiMood) {
        let stroke = StrokeStyle(lineWidth: 3.4, lineCap: .round)
        let thinStroke = StrokeStyle(lineWidth: 3.2, lineCap: .round)
        let ink = GraphicsContext.Shading.color(faceInk)

        // The static faces for list/row instances; the alive hero draws
        // through the scripted idle canvases instead.
        var g = ctx
        switch mood {
        case .content:
            g.fill(Path(ellipseIn: CGRect(x: 66, y: 82, width: 12, height: 12)), with: ink)
            g.fill(Path(ellipseIn: CGRect(x: 102, y: 82, width: 12, height: 12)), with: ink)
            g.fill(Path(ellipseIn: CGRect(x: 72, y: 84, width: 4, height: 4)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: 108, y: 84, width: 4, height: 4)), with: .color(.white))

        case .thriving:
            var leftEye = Path()
            leftEye.move(to: p(64, 90))
            leftEye.addCurve(to: p(78, 90), control1: p(67, 84), control2: p(75, 84))
            g.stroke(leftEye, with: ink, style: stroke)
            var rightEye = Path()
            rightEye.move(to: p(102, 90))
            rightEye.addCurve(to: p(116, 90), control1: p(105, 84), control2: p(113, 84))
            g.stroke(rightEye, with: ink, style: stroke)

        case .tired:
            var leftEye = Path()
            leftEye.move(to: p(66, 90))
            leftEye.addLine(to: p(78, 90))
            g.stroke(leftEye, with: ink, style: stroke)
            var rightEye = Path()
            rightEye.move(to: p(102, 90))
            rightEye.addLine(to: p(114, 90))
            g.stroke(rightEye, with: ink, style: stroke)

        case .unwell:
            var leftBrow = Path()
            leftBrow.move(to: p(66, 86))
            leftBrow.addCurve(to: p(79, 86), control1: p(69, 83), control2: p(77, 83))
            g.stroke(leftBrow, with: ink, style: thinStroke)
            var rightBrow = Path()
            rightBrow.move(to: p(101, 86))
            rightBrow.addCurve(to: p(114, 86), control1: p(104, 83), control2: p(112, 83))
            g.stroke(rightBrow, with: ink, style: thinStroke)
            g.fill(Path(ellipseIn: CGRect(x: 67.5, y: 87.5, width: 9, height: 9)), with: ink)
            g.fill(Path(ellipseIn: CGRect(x: 103.5, y: 87.5, width: 9, height: 9)), with: ink)

        case .sleeping:
            var leftEye = Path()
            leftEye.move(to: p(64, 88))
            leftEye.addCurve(to: p(78, 88), control1: p(67, 94), control2: p(75, 94))
            g.stroke(leftEye, with: ink, style: stroke)
            var rightEye = Path()
            rightEye.move(to: p(102, 88))
            rightEye.addCurve(to: p(116, 88), control1: p(105, 94), control2: p(113, 94))
            g.stroke(rightEye, with: ink, style: stroke)
        }

        // Mouth and mood extras.
        switch mood {
        case .content:
            var smile = Path()
            smile.move(to: p(80, 104))
            smile.addCurve(to: p(100, 104), control1: p(84, 109), control2: p(96, 109))
            ctx.stroke(smile, with: ink, style: stroke)

        case .thriving:
            var grin = Path()
            grin.move(to: p(78, 102))
            grin.addCurve(to: p(102, 102), control1: p(83, 110), control2: p(97, 110))
            ctx.stroke(grin, with: ink, style: stroke)

        case .tired:
            var mouth = Path()
            mouth.move(to: p(82, 106))
            mouth.addCurve(to: p(96, 106), control1: p(85, 104), control2: p(93, 104))
            ctx.stroke(mouth, with: ink, style: thinStroke)
            ctx.fill(sweatDrop(at: CGPoint(x: 126, y: 78)), with: .color(Color(hex: 0x8FD3F4)))

        case .sleeping:
            var mouth = Path()
            mouth.move(to: p(84, 106))
            mouth.addCurve(to: p(96, 106), control1: p(87, 109), control2: p(93, 109))
            ctx.stroke(mouth, with: ink, style: thinStroke)

        case .unwell:
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

/// Three z's drifting up from a sleeping Mochi, fading in sequence.
private struct SleepZzzView: View {
    let ink: Color
    let scale: CGFloat
    @State private var drifting = false

    var body: some View {
        ZStack {
            zLetter(size: 13, x: -10, y: 10, delay: 0)
            zLetter(size: 16, x: 2, y: -4, delay: 0.4)
            zLetter(size: 19, x: 16, y: -19, delay: 0.8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
        .accessibilityHidden(true)
    }

    private func zLetter(size: CGFloat, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        Text("z")
            .font(.system(size: size * scale, weight: .bold, design: .rounded))
            .foregroundStyle(ink.opacity(drifting ? 0.75 : 0.25))
            .offset(x: x * scale, y: (y - (drifting ? 3 : 0)) * scale)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(delay),
                value: drifting
            )
    }
}

/// A little puff of hearts drifting up when Mochi is petted. Idle at rest
/// (opacity 0); re-fires the rise each time `trigger` changes.
private struct HeartFloatView: View {
    let color: Color
    let scale: CGFloat
    let trigger: Int

    var body: some View {
        ZStack {
            heart(dx: -15, size: 13, delay: 0.0)
            heart(dx: 5, size: 17, delay: 0.06)
            heart(dx: 18, size: 12, delay: 0.13)
        }
        .accessibilityHidden(true)
    }

    private func heart(dx: CGFloat, size: CGFloat, delay: Double) -> some View {
        HeartShape()
            .fill(color)
            .frame(width: size * scale, height: size * scale)
            .keyframeAnimator(initialValue: HeartAnim(), trigger: trigger) { content, v in
                content
                    .opacity(v.opacity)
                    .scaleEffect(v.scale)
                    .offset(x: dx * scale, y: v.rise * scale)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    CubicKeyframe(1, duration: 0.2)
                    LinearKeyframe(1, duration: 0.5)
                    CubicKeyframe(0, duration: 0.4)
                }
                KeyframeTrack(\.rise) {
                    LinearKeyframe(0, duration: delay)
                    CubicKeyframe(-34, duration: 1.1)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.4, duration: delay)
                    SpringKeyframe(1, duration: 0.35)
                    LinearKeyframe(1, duration: 0.75)
                }
            }
    }
}

private struct HeartAnim {
    var opacity: Double = 0
    var rise: CGFloat = 0
    var scale: CGFloat = 0.4
}

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let topCurve = h * 0.3
        var path = Path()
        path.move(to: CGPoint(x: w / 2, y: h))
        path.addCurve(
            to: CGPoint(x: 0, y: topCurve),
            control1: CGPoint(x: w / 2, y: h * 0.72),
            control2: CGPoint(x: 0, y: h / 2)
        )
        path.addArc(
            center: CGPoint(x: w / 4, y: topCurve),
            radius: w / 4,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.addArc(
            center: CGPoint(x: w * 3 / 4, y: topCurve),
            radius: w / 4,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: w / 2, y: h),
            control1: CGPoint(x: w, y: h / 2),
            control2: CGPoint(x: w / 2, y: h * 0.72)
        )
        path.closeSubpath()
        return path
    }
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

#Preview("All states") {
    let moods: [(name: String, mood: MochiMood)] = [
        ("Thriving", .thriving),
        ("Content", .content),
        ("Tired", .tired),
        ("Unwell", .unwell),
        ("Sleeping", .sleeping),
    ]
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 28) {
            ForEach(moods, id: \.name) { item in
                VStack(spacing: 10) {
                    MochiPetView(mood: item.mood, size: 150, alive: true)
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
    }
    .background(MochiTheme.sesame.bg)
    .environment(\.mochiTheme, .sesame)
}

#Preview("Moods") {
    VStack(spacing: 12) {
        HStack(spacing: 12) {
            MochiPetView(mood: .thriving, size: 90)
            MochiPetView(mood: .content, size: 90)
            MochiPetView(mood: .tired, size: 90)
        }
        HStack(spacing: 12) {
            MochiPetView(mood: .unwell, size: 90)
            MochiPetView(mood: .sleeping, size: 90)
        }
    }
    .padding()
    .background(MochiTheme.sesame.bg)
    .environment(\.mochiTheme, .sesame)
}
