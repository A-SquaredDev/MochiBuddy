//
//  MochiScriptedIdle.swift
//  MochiBuddy
//
//  Scripted idle loops for the Mochi pet, one canvas per mood. Each mood is
//  a set of decoupled loops with unrelated periods (so the silhouette never
//  repeats), sampled per-frame off a shared clock. Content, tired, unwell and
//  sleeping are ported 1:1 from the design system's mood comps (dc.html);
//  thriving is our own in-code design. Transform-origins are applied as
//  translate-in / transform / translate-out, exactly like CSS
//  `transform-origin`.
//
//  - Thriving (in-house): the content loops made perkier - 3.4s breath, 7.5s
//    look/lean tour, quick 4.2s double blink - plus a quick happy hop every
//    9.5s with a cheek pop, widening grin and two sparkles on the landing.
//    `ThrivingIdleCanvas`.
//  - Content (`Mochi Content Animation v1`, sparkles cut by request):
//    4s squash-and-stretch breath with bob, shadow, mouth and crown jiggle;
//    a 9s look/lean tour of the room; a crisp 5.4s blink of lids that slide
//    down inside the body clip; and a 13s pleased wiggle-hop with cheek pop.
//    `ContentIdleCanvas`.
//  - Tired (`Mochi Tired Animation`): decoupled loops too - a 7.2s nod, 3.6s
//    breath/shadow/mouth, a 6s heavy-lidded lazy blink, sweat drips half a
//    loop apart and three staggered drifting z's. `TiredIdleCanvas`.
//  - Unwell (`Mochi Unwell Animation`): rest as exaggeration - held flat in a
//    lying-down squash while a single 5.6s laboured breath drives everything:
//    shadow, sinking lids and brows, a wavy grimace, flushing cheeks and a
//    fever fade. Steam, sweat and the dizzy-spiral eyes are deliberately
//    omitted (default-off in the comp). `UnwellIdleCanvas`.
//  - Sleeping (`Mochi Sleep Animation`): real stillness - a static flat-out
//    pose, a 4.6s snore-breath with heavy open-mouth breathing, a 9.2s
//    sub-degree slack sway, three staggered drifting z's, and every fourth
//    breath a little snuggling nuzzle. `SleepIdleCanvas`.
//

import SwiftUI

// MARK: - Shared art + sampling

/// The mochi body blob (viewBox 180x170), shared by every idle canvas.
private let mochiBodyPath: Path = {
    var body = Path()
    body.move(to: CGPoint(x: 90, y: 24))
    body.addCurve(to: CGPoint(x: 28, y: 86), control1: CGPoint(x: 52, y: 24), control2: CGPoint(x: 28, y: 50))
    body.addCurve(to: CGPoint(x: 90, y: 138), control1: CGPoint(x: 28, y: 116), control2: CGPoint(x: 50, y: 138))
    body.addCurve(to: CGPoint(x: 152, y: 86), control1: CGPoint(x: 130, y: 138), control2: CGPoint(x: 152, y: 116))
    body.addCurve(to: CGPoint(x: 90, y: 24), control1: CGPoint(x: 152, y: 50), control2: CGPoint(x: 128, y: 24))
    body.closeSubpath()
    return body
}()

/// The lighter crescent along the blob's top edge.
private let mochiHighlightPath: Path = {
    var highlight = Path()
    highlight.move(to: CGPoint(x: 90, y: 24))
    highlight.addCurve(to: CGPoint(x: 28, y: 86), control1: CGPoint(x: 52, y: 24), control2: CGPoint(x: 28, y: 50))
    highlight.addCurve(to: CGPoint(x: 31, y: 102), control1: CGPoint(x: 28, y: 92), control2: CGPoint(x: 29, y: 97))
    highlight.addCurve(to: CGPoint(x: 90, y: 52), control1: CGPoint(x: 37, y: 72), control2: CGPoint(x: 61, y: 52))
    highlight.addCurve(to: CGPoint(x: 149, y: 102), control1: CGPoint(x: 119, y: 52), control2: CGPoint(x: 143, y: 72))
    highlight.addCurve(to: CGPoint(x: 152, y: 86), control1: CGPoint(x: 151, y: 97), control2: CGPoint(x: 152, y: 92))
    highlight.addCurve(to: CGPoint(x: 90, y: 24), control1: CGPoint(x: 152, y: 50), control2: CGPoint(x: 128, y: 24))
    highlight.closeSubpath()
    return highlight
}()

/// A rounded lowercase z, traced once. The tired and sleeping idles used
/// to lay out a Text("z") glyph per z per frame - three glyph resolutions
/// at display rate, the hottest cost in this file. Unit-sized around the
/// origin; callers scale the context by the old font size and stroke.
private let zGlyphPath: Path = {
    var z = Path()
    z.move(to: CGPoint(x: -0.24, y: -0.26))
    z.addLine(to: CGPoint(x: 0.24, y: -0.26))
    z.addLine(to: CGPoint(x: -0.24, y: 0.26))
    z.addLine(to: CGPoint(x: 0.24, y: 0.26))
    return z
}()

/// Stroke for the unit z - the width is a fraction of the font size the
/// context is scaled by, matching the old semibold rounded glyph weight.
private let zGlyphStyle = StrokeStyle(lineWidth: 0.16, lineCap: .round, lineJoin: .round)

/// Applies a transform about (ox, oy), matching CSS `transform-origin`.
private func origin(_ ctx: inout GraphicsContext, _ ox: CGFloat, _ oy: CGFloat, _ body: (inout GraphicsContext) -> Void) {
    ctx.translateBy(x: ox, y: oy)
    body(&ctx)
    ctx.translateBy(x: -ox, y: -oy)
}

/// Position within a looping animation of `period` seconds, 0...1.
private func phase(_ now: Double, period: Double, delay: Double = 0) -> CGFloat {
    var p = (now - delay).truncatingRemainder(dividingBy: period) / period
    if p < 0 { p += 1 }
    return CGFloat(p)
}

/// Eased 0 -> 1 -> 0 over one period - what CSS's symmetric 0/50/100%
/// keyframes with sine-ish easing produce.
private func wave(_ now: Double, period: Double) -> CGFloat {
    CGFloat((1 - cos(2 * .pi * Double(phase(now, period: period)))) / 2)
}

/// Samples a keyframe table at t, easing between stops with smoothstep.
private func kf(_ t: CGFloat, _ stops: [(CGFloat, CGFloat)]) -> CGFloat {
    guard let first = stops.first else { return 0 }
    if t <= first.0 { return first.1 }
    for i in 1..<stops.count {
        let (t0, v0) = stops[i - 1]
        let (t1, v1) = stops[i]
        if t <= t1 {
            let f = (t - t0) / max(t1 - t0, 0.0001)
            let e = f * f * (3 - 2 * f) // smoothstep
            return v0 + (v1 - v0) * e
        }
    }
    return stops.last!.1
}

// MARK: - Thriving idle

/// The happy thriving idle - our own design rather than a comp port. It is
/// the content loops made perkier: a 3.4s squash-and-stretch breath (bob,
/// shadow and crown jiggle in phase), a 7.5s look/lean tour with slightly
/// bigger saccades, and a quick double blink every 4.2s. The extra is a
/// quick happy hop every 9.5s - crouch, spring to -22px with an in-air
/// stretch and tilt, landing squash, one snappy rebound, all inside ~1.8s -
/// with the grin widening, cheeks popping and two diamond sparkles on the
/// landing.
struct ThrivingIdleCanvas: View {
    var theme: MochiTheme
    var size: CGFloat
    var faceInk: Color
    var showsSparkles: Bool = true
    /// Host-driven: true while the pet is covered by a sheet, on an
    /// unselected tab, or the scene is inactive - the timeline stops
    /// ticking entirely instead of rendering unseen frames.
    var paused: Bool = false

    var body: some View {
        // 60fps cap: the slowest track is a multi-second loop, so ProMotion's
        // 120Hz doubles the work for no visible gain.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, canvasSize: canvasSize, now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size * 170 / 180)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, canvasSize: CGSize, now: Double) {
        let s = canvasSize.width / 180
        ctx.scaleBy(x: s, y: s)

        let breathT = phase(now, period: 3.4)  // breath, bob, shadow, jiggle
        let lookT = phase(now, period: 7.5)    // look + lean
        let blinkT = phase(now, period: 4.2)
        let hopT = phase(now, period: 9.5)     // hop, grin, cheeks, heart

        // Ground shadow - eases with the breath, shrinks and fades under the
        // hop, swells on the landing.
        var shadow = ctx
        shadow.opacity = Double(kf(breathT, Thriving.shadowOpacity) * kf(hopT, Thriving.hopShadowOpacity))
        origin(&shadow, 90, 150) {
            $0.scaleBy(x: kf(breathT, Thriving.shadowScaleX) * kf(hopT, Thriving.hopShadowScaleX), y: 1)
        }
        shadow.fill(
            Path(ellipseIn: CGRect(x: 40, y: 141, width: 100, height: 18)),
            with: .color(.black.opacity(0.16))
        )

        // Happy hop - crouch, spring, land, one small rebound. Origin 50% 100%.
        var g = ctx
        origin(&g, 90, 138) {
            $0.translateBy(x: 0, y: kf(hopT, Thriving.hopTy))
            $0.rotate(by: .degrees(Double(kf(hopT, Thriving.hopRot))))
            $0.scaleBy(x: kf(hopT, Thriving.hopScaleX), y: kf(hopT, Thriving.hopScaleY))
        }

        // Bob - the breath lifts him off the ground (pure translate).
        g.translateBy(x: 0, y: kf(breathT, Thriving.bobTy))

        // Lean - the body follows each glance a beat later.
        origin(&g, 90, 133.4) {
            $0.rotate(by: .degrees(Double(kf(lookT, Thriving.leanRot))))
            $0.translateBy(x: kf(lookT, Thriving.leanTx), y: 0)
        }

        // Breath - a perky +-6.5% squash and stretch.
        origin(&g, 90, 138) {
            $0.scaleBy(x: kf(breathT, Thriving.breathScaleX), y: kf(breathT, Thriving.breathScaleY))
        }

        // Crown jiggle so the blob never reads rigid.
        origin(&g, 90, 128.9) {
            $0.rotate(by: .degrees(Double(kf(breathT, Thriving.jiggleRot))))
        }

        g.fill(mochiBodyPath, with: .color(theme.pet))
        g.fill(mochiHighlightPath, with: .color(theme.pet2.opacity(0.55)))

        // Cheeks pop and brighten on the hop.
        drawCheek(&g, cx: 56, t: hopT)
        drawCheek(&g, cx: 124, t: hopT)

        // Eyes - big sparkly ovals with double glints, touring the room, with
        // a quick double blink squeeze.
        var eyes = g
        eyes.translateBy(x: kf(lookT, Thriving.lookTx), y: kf(lookT, Thriving.lookTy))
        origin(&eyes, 90, 88) { $0.scaleBy(x: 1, y: kf(blinkT, Thriving.blinkScaleY)) }
        let ink = GraphicsContext.Shading.color(faceInk)
        eyes.fill(Path(ellipseIn: CGRect(x: 62.5, y: 79, width: 15, height: 18)), with: ink)
        eyes.fill(Path(ellipseIn: CGRect(x: 102.5, y: 79, width: 15, height: 18)), with: ink)
        eyes.fill(Path(ellipseIn: CGRect(x: 70, y: 82, width: 5.2, height: 5.2)), with: .color(.white))
        eyes.fill(Path(ellipseIn: CGRect(x: 110, y: 82, width: 5.2, height: 5.2)), with: .color(.white))
        eyes.fill(Path(ellipseIn: CGRect(x: 66.3, y: 90.1, width: 2.6, height: 2.6)), with: .color(.white.opacity(0.8)))
        eyes.fill(Path(ellipseIn: CGRect(x: 106.3, y: 90.1, width: 2.6, height: 2.6)), with: .color(.white.opacity(0.8)))

        // Full open smile - a filled grin with the tongue tucked into the
        // bottom, opening even wider while he's in the air.
        var mouth = g
        origin(&mouth, 90, 102) {
            $0.scaleBy(x: kf(hopT, Thriving.mouthScaleX), y: kf(hopT, Thriving.mouthScaleY))
        }
        mouth.fill(thrivingGrinPath, with: ink)
        var tongue = mouth
        tongue.clip(to: thrivingGrinPath)
        tongue.fill(thrivingTonguePath, with: .color(theme.petCheek.opacity(0.9)))

        // Two diamond sparkles blink once on the landing.
        if showsSparkles {
            drawSparkle(&ctx, cx: 146, cy: 69, tip: 9, waist: 2.6, t: hopT)
            drawSparkle(&ctx, cx: 36, cy: 80.5, tip: 6.5, waist: 1.9, t: phase(now, period: 9.5, delay: 0.5))
        }
    }

    private func drawCheek(_ ctx: inout GraphicsContext, cx: CGFloat, t: CGFloat) {
        var g = ctx
        g.opacity = Double(kf(t, Thriving.cheekOpacity))
        origin(&g, cx, 102) {
            let sc = kf(t, Thriving.cheekScale)
            $0.scaleBy(x: sc, y: sc)
        }
        g.fill(Path(ellipseIn: CGRect(x: cx - 11, y: 94, width: 22, height: 16)), with: .color(theme.petCheek))
    }

    /// Four-point diamond sparkle scaling and spinning in for one blink.
    private func drawSparkle(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, tip: CGFloat, waist: CGFloat, t: CGFloat) {
        let op = Double(kf(t, Thriving.sparkleOpacity))
        guard op > 0.001 else { return }
        var g = ctx
        g.opacity = op
        origin(&g, cx, cy) {
            let sc = kf(t, Thriving.sparkleScale)
            $0.scaleBy(x: sc, y: sc)
            $0.rotate(by: .degrees(Double(kf(t, Thriving.sparkleRot))))
        }
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - tip))
        p.addLine(to: CGPoint(x: cx + waist, y: cy - waist))
        p.addLine(to: CGPoint(x: cx + tip, y: cy))
        p.addLine(to: CGPoint(x: cx + waist, y: cy + waist))
        p.addLine(to: CGPoint(x: cx, y: cy + tip))
        p.addLine(to: CGPoint(x: cx - waist, y: cy + waist))
        p.addLine(to: CGPoint(x: cx - tip, y: cy))
        p.addLine(to: CGPoint(x: cx - waist, y: cy - waist))
        p.closeSubpath()
        g.fill(p, with: .color(theme.primary))
    }
}

/// The thriving grin and tucked tongue - constant geometry, only the
/// mouth transform animates, so both are traced once.
private let thrivingGrinPath: Path = {
    var grin = Path()
    grin.move(to: CGPoint(x: 78.5, y: 102))
    grin.addLine(to: CGPoint(x: 101.5, y: 102))
    grin.addCurve(to: CGPoint(x: 78.5, y: 102), control1: CGPoint(x: 101.5, y: 116.5), control2: CGPoint(x: 78.5, y: 116.5))
    grin.closeSubpath()
    return grin
}()

private let thrivingTonguePath = Path(ellipseIn: CGRect(x: 83, y: 107.5, width: 14, height: 9))

/// Thriving keyframe tables, as fractions of each track's own loop.
private enum Thriving {
    static let breathScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 0.94), (0.72, 1.065), (1, 1)]
    static let breathScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 1.075), (0.72, 0.94), (1, 1)]
    static let bobTy: [(CGFloat, CGFloat)] = [(0, 0), (0.38, -9), (0.72, 2), (1, 0)]
    static let shadowScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 0.85), (0.72, 1.07), (1, 1)]
    static let shadowOpacity: [(CGFloat, CGFloat)] = [(0, 0.5), (0.38, 0.36), (0.72, 0.56), (1, 0.5)]
    static let jiggleRot: [(CGFloat, CGFloat)] = [(0, 0), (0.30, 1.8), (0.65, -1.8), (1, 0)]

    /// 7.5s tour, a touch wider-eyed than content's.
    static let lookTx: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.17, -8), (0.31, -8), (0.34, -4), (0.45, -4),
        (0.48, 8), (0.64, 8), (0.67, 5), (0.78, 5), (0.82, 0), (1, 0),
    ]
    static let lookTy: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.17, 1.5), (0.31, 1.5), (0.34, -3.5), (0.45, -3.5),
        (0.48, 1.5), (0.64, 1.5), (0.67, -3), (0.78, -3), (0.82, 0), (1, 0),
    ]
    static let leanRot: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.19, -5), (0.31, -5), (0.36, -2), (0.45, -2),
        (0.52, 5), (0.64, 5), (0.69, 2), (0.78, 2), (0.86, 0), (1, 0),
    ]
    static let leanTx: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.19, -3), (0.31, -3), (0.36, -1), (0.45, -1),
        (0.52, 3), (0.64, 3), (0.69, 1), (0.78, 1), (0.86, 0), (1, 0),
    ]

    /// 4.2s: a quick, crisp double blink.
    static let blinkScaleY: [(CGFloat, CGFloat)] = [
        (0, 1), (0.55, 1), (0.578, 0.06), (0.606, 1), (0.634, 0.06), (0.662, 1), (1, 1),
    ]

    /// 9.5s cadence, but the bounce itself is quick: crouch (~0.3s), spring
    /// to -22 (~0.5s), land (~0.45s), one snappy rebound, settled again
    /// within ~1.8s.
    static let hopTy: [(CGFloat, CGFloat)] = [
        (0, 0), (0.30, 0), (0.33, 3), (0.385, -22), (0.432, 0), (0.459, -6), (0.49, 0), (1, 0),
    ]
    static let hopScaleX: [(CGFloat, CGFloat)] = [
        (0, 1), (0.30, 1), (0.33, 1.08), (0.385, 0.94), (0.432, 1.12), (0.49, 1), (1, 1),
    ]
    static let hopScaleY: [(CGFloat, CGFloat)] = [
        (0, 1), (0.30, 1), (0.33, 0.92), (0.385, 1.08), (0.432, 0.88), (0.49, 1), (1, 1),
    ]
    static let hopRot: [(CGFloat, CGFloat)] = [
        (0, 0), (0.30, 0), (0.36, -4), (0.41, 3), (0.46, -1), (0.49, 0), (1, 0),
    ]
    static let hopShadowScaleX: [(CGFloat, CGFloat)] = [
        (0, 1), (0.30, 1), (0.385, 0.85), (0.432, 1.06), (0.49, 1), (1, 1),
    ]
    static let hopShadowOpacity: [(CGFloat, CGFloat)] = [
        (0, 1), (0.30, 1), (0.385, 0.55), (0.432, 1.05), (0.49, 1), (1, 1),
    ]
    static let cheekScale: [(CGFloat, CGFloat)] = [(0, 1), (0.31, 1), (0.40, 1.25), (0.52, 1), (1, 1)]
    static let cheekOpacity: [(CGFloat, CGFloat)] = [(0, 0.55), (0.31, 0.55), (0.40, 0.8), (0.52, 0.55), (1, 0.55)]
    static let mouthScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.31, 1), (0.385, 1.15), (0.46, 1.15), (0.53, 1), (1, 1)]
    static let mouthScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.31, 1), (0.385, 1.3), (0.46, 1.3), (0.53, 1), (1, 1)]
    static let sparkleOpacity: [(CGFloat, CGFloat)] = [(0, 0), (0.41, 0), (0.46, 0.9), (0.54, 0), (1, 0)]
    static let sparkleScale: [(CGFloat, CGFloat)] = [(0, 0.2), (0.41, 0.2), (0.46, 1), (0.54, 0.35), (1, 0.2)]
    static let sparkleRot: [(CGFloat, CGFloat)] = [(0, 0), (0.41, 0), (0.54, 60), (1, 60)]
}

// MARK: - Content idle

/// The quietly-pleased content idle, ported 1:1 from the design system's
/// `Mochi Content Animation v1` (dc.html), minus its sparkles (cut by
/// request). Decoupled loops, each sampled against its own period: 4s
/// squash-and-stretch breath (with bob, shadow, mouth pulse and crown jiggle
/// in phase), a 9s saccade look/lean tour, a crisp 5.4s blink of pet-colored
/// lids sliding down inside the body clip, and a 13s pleased wiggle-hop with
/// cheek pop.
struct ContentIdleCanvas: View {
    var theme: MochiTheme
    var size: CGFloat
    var faceInk: Color
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, canvasSize: canvasSize, now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size * 170 / 180)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, canvasSize: CGSize, now: Double) {
        let s = canvasSize.width / 180
        ctx.scaleBy(x: s, y: s)

        let breathT = phase(now, period: 4)   // breath, bob, shadow, mouth, jiggle
        let lookT = phase(now, period: 9)     // look + lean
        let wiggleT = phase(now, period: 13)  // wiggle-hop, cheeks, sparkles

        // Ground shadow - shrinks and fades as he stretches tall, swells back
        // on the exhale.
        var shadow = ctx
        shadow.opacity = Double(kf(breathT, ContentV1.shadowOpacity))
        origin(&shadow, 90, 150) { $0.scaleBy(x: kf(breathT, ContentV1.shadowScaleX), y: 1) }
        shadow.fill(
            Path(ellipseIn: CGRect(x: 40, y: 141, width: 100, height: 18)),
            with: .color(.black.opacity(0.16))
        )

        // Wiggle-hop - every 13s, on the bouncy Mochi curve. Origin 50% 96%.
        var g = ctx
        origin(&g, 90, 133.4) {
            $0.translateBy(x: 0, y: kf(wiggleT, ContentV1.wiggleTy))
            $0.rotate(by: .degrees(Double(kf(wiggleT, ContentV1.wiggleRot))))
        }

        // Bob - the breath lifts him 8px off the ground (pure translate).
        g.translateBy(x: 0, y: kf(breathT, ContentV1.bobTy))

        // Lean - the body follows each glance a beat later. Origin 50% 96%.
        origin(&g, 90, 133.4) {
            $0.rotate(by: .degrees(Double(kf(lookT, ContentV1.leanRot))))
            $0.translateBy(x: kf(lookT, ContentV1.leanTx), y: 0)
        }

        // Breath - +-6% squash and stretch. Origin 50% 100%.
        origin(&g, 90, 138) {
            $0.scaleBy(x: kf(breathT, ContentV1.breathScaleX), y: kf(breathT, ContentV1.breathScaleY))
        }

        // Crown jiggle - +-1.6 degrees so the blob never reads rigid.
        origin(&g, 90, 128.9) {
            $0.rotate(by: .degrees(Double(kf(breathT, ContentV1.jiggleRot))))
        }

        g.fill(mochiBodyPath, with: .color(theme.pet))

        // Eyes - big round pupils with two glints, touring the room.
        let ink = GraphicsContext.Shading.color(faceInk)
        var eyes = g
        eyes.translateBy(x: kf(lookT, ContentV1.lookTx), y: kf(lookT, ContentV1.lookTy))
        eyes.fill(Path(ellipseIn: CGRect(x: 65, y: 80.4, width: 14, height: 15.2)), with: ink)
        eyes.fill(Path(ellipseIn: CGRect(x: 101, y: 80.4, width: 14, height: 15.2)), with: ink)
        eyes.fill(Path(ellipseIn: CGRect(x: 72.2, y: 83.2, width: 4.4, height: 4.4)), with: .color(.white.opacity(0.92)))
        eyes.fill(Path(ellipseIn: CGRect(x: 108.2, y: 83.2, width: 4.4, height: 4.4)), with: .color(.white.opacity(0.92)))
        eyes.fill(Path(ellipseIn: CGRect(x: 68.5, y: 90.3, width: 2.2, height: 2.2)), with: .color(.white.opacity(0.55)))
        eyes.fill(Path(ellipseIn: CGRect(x: 104.5, y: 90.3, width: 2.2, height: 2.2)), with: .color(.white.opacity(0.55)))

        // Blink - big pet-colored lids parked above the eyes (ty -72) drop to
        // +12 for one crisp double-tap, clipped to the body so they read as
        // the blob's own surface.
        var lids = g
        lids.clip(to: mochiBodyPath)
        lids.translateBy(x: 0, y: kf(phase(now, period: 5.4), ContentV1.blinkTy))
        drawBlinkLid(&lids, x: 56)
        drawBlinkLid(&lids, x: 88)

        // Top highlight sits over the lids, exactly like the SVG order.
        g.fill(mochiHighlightPath, with: .color(theme.pet2.opacity(0.55)))

        // Cheeks - pop 1.3x and brighten on the hop.
        drawCheek(&g, cx: 54, t: wiggleT)
        drawCheek(&g, cx: 126, t: wiggleT)

        // Mouth - soft open smile pulsing with the breath. Origin 50% 0%.
        var mouth = g
        origin(&mouth, 89.7, 106) {
            $0.scaleBy(x: kf(breathT, ContentV1.mouthScaleX), y: kf(breathT, ContentV1.mouthScaleY))
        }
        mouth.stroke(contentLipPath, with: ink, style: contentLipStyle)

    }

    /// One lid: `M x 26 h36 v66 a30 22 0 0 1 -36 0 z` - a tall pet-colored
    /// slab whose bottom edge bows ~4.4px down. Traced once at x = 0 and
    /// translated per eye.
    private func drawBlinkLid(_ ctx: inout GraphicsContext, x: CGFloat) {
        var g = ctx
        g.translateBy(x: x, y: 0)
        g.fill(contentLidPath, with: .color(theme.pet))
    }

    private func drawCheek(_ ctx: inout GraphicsContext, cx: CGFloat, t: CGFloat) {
        var g = ctx
        g.opacity = Double(kf(t, ContentV1.cheekOpacity))
        origin(&g, cx, 102) {
            let sc = kf(t, ContentV1.cheekScale)
            $0.scaleBy(x: sc, y: sc)
        }
        g.fill(Path(ellipseIn: CGRect(x: cx - 12, y: 94, width: 24, height: 16)), with: .color(theme.petCheek))
    }
}

private let contentLidPath: Path = {
    var lid = Path()
    lid.move(to: CGPoint(x: 0, y: 26))
    lid.addLine(to: CGPoint(x: 36, y: 26))
    lid.addLine(to: CGPoint(x: 36, y: 92))
    lid.addQuadCurve(to: CGPoint(x: 0, y: 92), control: CGPoint(x: 18, y: 100.8))
    lid.closeSubpath()
    return lid
}()

private let contentLipPath: Path = {
    var lip = Path()
    lip.move(to: CGPoint(x: 81, y: 106))
    lip.addCurve(to: CGPoint(x: 98.4, y: 106), control1: CGPoint(x: 84.6, y: 111.2), control2: CGPoint(x: 94.8, y: 111.2))
    return lip
}()

private let contentLipStyle = StrokeStyle(lineWidth: 3.2, lineCap: .round)

/// Content v1 keyframe tables, as fractions of each track's own loop.
private enum ContentV1 {
    /// 4s breath: stretch tall on the inhale (38%), squash wide on the
    /// exhale (72%) - `ct-breath`.
    static let breathScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 0.945), (0.72, 1.06), (1, 1)]
    static let breathScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 1.07), (0.72, 0.945), (1, 1)]
    static let bobTy: [(CGFloat, CGFloat)] = [(0, 0), (0.38, -8), (0.72, 2), (1, 0)]
    static let shadowScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 0.86), (0.72, 1.06), (1, 1)]
    static let shadowOpacity: [(CGFloat, CGFloat)] = [(0, 0.5), (0.38, 0.34), (0.72, 0.56), (1, 0.5)]
    static let mouthScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 0.94), (0.72, 1.12), (1, 1)]
    static let mouthScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.38, 0.9), (0.72, 1.2), (1, 1)]
    static let jiggleRot: [(CGFloat, CGFloat)] = [(0, 0), (0.30, 1.6), (0.65, -1.6), (1, 0)]

    /// 9s tour: quick saccades with long curious holds - `ct-look`.
    static let lookTx: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.17, -7.5), (0.31, -7.5), (0.34, -4), (0.45, -4),
        (0.48, 7.5), (0.64, 7.5), (0.67, 5), (0.78, 5), (0.82, 0), (1, 0),
    ]
    static let lookTy: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.17, 1.5), (0.31, 1.5), (0.34, -3.5), (0.45, -3.5),
        (0.48, 1.5), (0.64, 1.5), (0.67, -3), (0.78, -3), (0.82, 0), (1, 0),
    ]
    /// The body follows each glance a beat later - `ct-lean`.
    static let leanRot: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.19, -4.5), (0.31, -4.5), (0.36, -2), (0.45, -2),
        (0.52, 4.5), (0.64, 4.5), (0.69, 2), (0.78, 2), (0.86, 0), (1, 0),
    ]
    static let leanTx: [(CGFloat, CGFloat)] = [
        (0, 0), (0.14, 0), (0.19, -3), (0.31, -3), (0.36, -1), (0.45, -1),
        (0.52, 3), (0.64, 3), (0.69, 1), (0.78, 1), (0.86, 0), (1, 0),
    ]

    /// 5.4s: lids parked at -72 drop to +12 for one crisp blink - `ct-blink`.
    static let blinkTy: [(CGFloat, CGFloat)] = [
        (0, -72), (0.82, -72), (0.85, 12), (0.875, 12), (0.905, -72), (1, -72),
    ]

    /// 13s: rest, hop with alternating tilt, settle - `ct-wiggle`.
    static let wiggleTy: [(CGFloat, CGFloat)] = [
        (0, 0), (0.68, 0), (0.73, -19), (0.79, 0), (0.84, -8), (0.89, 0), (1, 0),
    ]
    static let wiggleRot: [(CGFloat, CGFloat)] = [
        (0, 0), (0.68, 0), (0.73, -6), (0.79, 5), (0.84, -3), (0.89, 1.5), (0.94, 0), (1, 0),
    ]
    static let cheekScale: [(CGFloat, CGFloat)] = [(0, 1), (0.68, 1), (0.76, 1.3), (0.94, 1), (1, 1)]
    static let cheekOpacity: [(CGFloat, CGFloat)] = [(0, 0.5), (0.68, 0.5), (0.76, 0.78), (0.94, 0.5), (1, 0.5)]
}

// MARK: - Tired idle

/// The drowsy tired idle. Its CSS is several infinite loops with different
/// periods rather than one beat, so each track samples its own loop here:
/// nod 7.2s, breath/shadow/mouth 3.6s (in phase, like CSS animations started
/// together), blink 6s, sweat drips 7.2s half a loop apart, z's 3.6s on a
/// 1.2s stagger. The design's brow track ships default-off, so it isn't here.
struct TiredIdleCanvas: View {
    var theme: MochiTheme
    var size: CGFloat
    var faceInk: Color
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, canvasSize: canvasSize, now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size * 170 / 180)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, canvasSize: CGSize, now: Double) {
        let s = canvasSize.width / 180
        ctx.scaleBy(x: s, y: s)

        let soft = wave(now, period: 3.6) // breath, shadow, mouth
        let nod = wave(now, period: 7.2)

        // Ground shadow - swells and darkens a touch with each breath.
        var shadow = ctx
        shadow.opacity = 0.5 + 0.12 * Double(soft)
        origin(&shadow, 90, 150) { $0.scaleBy(x: 1 + 0.05 * soft, y: 1) }
        shadow.fill(
            Path(ellipseIn: CGRect(x: 40, y: 141, width: 100, height: 18)),
            with: .color(.black.opacity(0.16))
        )

        // Nod - a slow +-1.5 degree sway with a 4px sink, like nearly dozing off.
        var lean = ctx
        origin(&lean, 90, 140) {
            $0.translateBy(x: 0, y: 4 * nod)
            $0.rotate(by: .degrees(Double(-1.5 + 3 * nod)))
        }

        // Breath - 3.5% squash, inside the nod.
        var body = lean
        origin(&body, 90, 140) {
            $0.scaleBy(x: 1 + 0.035 * soft, y: 1 - 0.035 * soft)
        }
        body.fill(mochiBodyPath, with: .color(theme.pet))
        body.fill(mochiHighlightPath, with: .color(theme.pet2.opacity(0.55)))
        body.fill(Path(ellipseIn: CGRect(x: 42, y: 94, width: 24, height: 16)), with: .color(theme.petCheek.opacity(0.5)))
        body.fill(Path(ellipseIn: CGRect(x: 114, y: 94, width: 24, height: 16)), with: .color(theme.petCheek.opacity(0.5)))

        // Eyes - full round pupils that the heavy lids rest low over.
        let ink = GraphicsContext.Shading.color(faceInk)
        body.fill(Path(ellipseIn: CGRect(x: 65.5, y: 82.5, width: 13, height: 13)), with: ink)
        body.fill(Path(ellipseIn: CGRect(x: 101.5, y: 82.5, width: 13, height: 13)), with: ink)
        body.fill(Path(ellipseIn: CGRect(x: 72.2, y: 85.2, width: 3.6, height: 3.6)), with: .color(.white.opacity(0.9)))
        body.fill(Path(ellipseIn: CGRect(x: 108.2, y: 85.2, width: 3.6, height: 3.6)), with: .color(.white.opacity(0.9)))

        // Lids - pet-colored shades half way down the pupils; the 6s blink
        // drops them 9px (one lazy held close, one quick re-close) and back.
        var lids = body
        lids.translateBy(x: 0, y: kf(phase(now, period: 6), Tired.blinkDrop))
        drawLid(&lids, x: 60)
        drawLid(&lids, x: 98)

        // Mouth - a soft little sag that swells 8 x 15% with the breath.
        var mouth = body
        origin(&mouth, 89.2, 107) {
            $0.scaleBy(x: 1 + 0.08 * soft, y: 1 + 0.15 * soft)
        }
        mouth.stroke(tiredLipPath, with: ink, style: tiredLipStyle)

        // Sweat drips - form, slide 30px and vanish, half a loop apart.
        drawDrip(&ctx, x: 138, y: 74, t: phase(now, period: 7.2))
        drawDrip(&ctx, x: 42, y: 80, t: phase(now, period: 7.2, delay: 3.4))

        // Three z's drifting up-right, biggest last.
        drawZ(&ctx, x: 132, y: 92, fontSize: 16, t: phase(now, period: 3.6))
        drawZ(&ctx, x: 142, y: 78, fontSize: 21, t: phase(now, period: 3.6, delay: 1.2))
        drawZ(&ctx, x: 150, y: 62, fontSize: 26, t: phase(now, period: 3.6, delay: 2.4))
    }

    /// One lid: `M x 68 h22 v16 a22 22 0 0 1 -22 0 z` - a pet-colored shade
    /// whose bottom edge bows ~3px down, plus the lash line along that edge.
    /// Both traced once at x = 0 and translated per eye.
    private func drawLid(_ ctx: inout GraphicsContext, x: CGFloat) {
        var g = ctx
        g.translateBy(x: x, y: 0)
        g.fill(tiredLidPath, with: .color(theme.pet))
        g.stroke(tiredLashPath, with: .color(faceInk), style: tiredLashStyle)
    }

    private func drawDrip(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, t: CGFloat) {
        let op = Double(kf(t, Tired.dripOpacity))
        guard op > 0.001 else { return }
        var g = ctx
        g.opacity = op
        origin(&g, x, y) {
            $0.translateBy(x: 0, y: kf(t, Tired.dripTy))
            let sc = kf(t, Tired.dripScale)
            $0.scaleBy(x: sc, y: sc)
        }
        g.translateBy(x: x, y: y)
        g.fill(dripPath, with: .color(Color(hex: 0x8FD3F4)))
    }

    /// One drifting z. The SVG anchors text at the baseline start; Canvas
    /// anchors at center, so the glyph center is estimated from the font
    /// size. Strokes the pre-traced unit z scaled by the font size.
    private func drawZ(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, fontSize: CGFloat, t: CGFloat) {
        let op = Double(kf(t, Tired.zOpacity))
        guard op > 0.001 else { return }
        let cx = x + 0.30 * fontSize
        let cy = y - 0.26 * fontSize
        var g = ctx
        g.opacity = op
        origin(&g, cx, cy) {
            $0.translateBy(x: kf(t, Tired.zTx), y: kf(t, Tired.zTy))
            let sc = kf(t, Tired.zScale)
            $0.scaleBy(x: sc, y: sc)
            $0.rotate(by: .degrees(Double(kf(t, Tired.zRot))))
        }
        g.translateBy(x: cx, y: cy)
        g.scaleBy(x: fontSize, y: fontSize)
        g.stroke(zGlyphPath, with: .color(theme.primary), style: zGlyphStyle)
    }

}

private let tiredLidPath: Path = {
    var lid = Path()
    lid.move(to: CGPoint(x: 0, y: 68))
    lid.addLine(to: CGPoint(x: 22, y: 68))
    lid.addLine(to: CGPoint(x: 22, y: 84))
    lid.addQuadCurve(to: CGPoint(x: 0, y: 84), control: CGPoint(x: 11, y: 89.9))
    lid.closeSubpath()
    return lid
}()

private let tiredLashPath: Path = {
    var lash = Path()
    lash.move(to: CGPoint(x: 0.5, y: 84))
    lash.addCurve(to: CGPoint(x: 21.5, y: 84), control1: CGPoint(x: 5, y: 87.4), control2: CGPoint(x: 17.5, y: 87.4))
    return lash
}()

private let tiredLashStyle = StrokeStyle(lineWidth: 2.8, lineCap: .round)

private let tiredLipPath: Path = {
    var lip = Path()
    lip.move(to: CGPoint(x: 84, y: 107))
    lip.addCurve(to: CGPoint(x: 94.4, y: 107), control1: CGPoint(x: 86.4, y: 109.6), control2: CGPoint(x: 92, y: 109.6))
    return lip
}()

private let tiredLipStyle = StrokeStyle(lineWidth: 3, lineCap: .round)

/// Teardrop at the origin: `c4 6 4 11 0 11 s-4-5 0-11z`.
private let dripPath: Path = {
    var drop = Path()
    drop.move(to: CGPoint(x: 0, y: 0))
    drop.addCurve(to: CGPoint(x: 0, y: 11), control1: CGPoint(x: 4, y: 6), control2: CGPoint(x: 4, y: 11))
    drop.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -4, y: 11), control2: CGPoint(x: -4, y: 6))
    drop.closeSubpath()
    return drop
}()

/// Tired keyframe tables, as fractions of each track's own loop.
private enum Tired {
    /// 6s: rest, one lazy full close (held), reopen, a quick second close,
    /// then settle just above rest - `tired-blink`.
    static let blinkDrop: [(CGFloat, CGFloat)] = [
        (0, 0), (0.30, 0), (0.40, 9), (0.46, 9), (0.58, 0), (0.72, 9), (0.80, 1), (1, 0),
    ]
    static let dripTy: [(CGFloat, CGFloat)] = [(0, 0), (0.12, 0), (0.46, 24), (0.54, 30), (1, 30)]
    static let dripScale: [(CGFloat, CGFloat)] = [(0, 0.5), (0.12, 1), (0.46, 1.15), (0.54, 0.35), (1, 0.35)]
    static let dripOpacity: [(CGFloat, CGFloat)] = [(0, 0), (0.12, 1), (0.46, 0.95), (0.54, 0), (1, 0)]
    static let zOpacity: [(CGFloat, CGFloat)] = [(0, 0), (0.18, 1), (0.70, 0.85), (1, 0)]
    static let zTx: [(CGFloat, CGFloat)] = [(0, 0), (1, 12)]
    static let zTy: [(CGFloat, CGFloat)] = [(0, 0), (1, -30)]
    static let zScale: [(CGFloat, CGFloat)] = [(0, 0.55), (1, 1.25)]
    static let zRot: [(CGFloat, CGFloat)] = [(0, -10), (1, 12)]
}

// MARK: - Unwell idle

/// The resting-it-off unwell idle, ported 1:1 from the design system's
/// `Mochi Unwell Animation` (dc.html). The exaggeration is the pose and the
/// stillness: held flat in a static lying-down squash (13% wider, 80% tall)
/// while one 5.6s laboured breath drives everything else - shadow, sinking
/// lids and brows, the wavy grimace, flushing cheeks and a whole-body fever
/// fade. Steam, sweat and the dizzy-spiral eyes are deliberately omitted
/// (default-off in the comp).
struct UnwellIdleCanvas: View {
    var theme: MochiTheme
    var size: CGFloat
    var faceInk: Color
    /// The mood saturation MochiPetView would otherwise apply as a second
    /// whole-view filter pass; folded into the fever-fade filter here so
    /// the unwell pet pays one color pass per frame, never two.
    var baseSaturation: Double = 1
    var paused: Bool = false

    var body: some View {
        // 30fps: the mood is near-static by design ("rest as exaggeration"),
        // and every frame pays a whole-canvas color filter.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, canvasSize: canvasSize, now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size * 170 / 180)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, canvasSize: CGSize, now: Double) {
        let s = canvasSize.width / 180
        ctx.scaleBy(x: s, y: s)

        let t = phase(now, period: 5.6)

        // Fever fade - colour drains slightly on each exhale. The mood's
        // baseline saturation rides in here (baseSaturation) so the whole
        // pet pays a single filter pass.
        ctx.addFilter(.saturation(baseSaturation * Double(kf(t, Unwell.fadeSaturation))))
        ctx.addFilter(.brightness(Double(kf(t, Unwell.fadeBrightness))))

        // Ground shadow - softens with the shallow breath.
        var shadow = ctx
        shadow.opacity = Double(kf(t, Unwell.shadowOpacity))
        origin(&shadow, 90, 152) { $0.scaleBy(x: kf(t, Unwell.shadowScaleX), y: 1) }
        shadow.fill(
            Path(ellipseIn: CGRect(x: 40, y: 143, width: 100, height: 18)),
            with: .color(.black.opacity(0.2))
        )

        // Lying-down pose - a static squash held the whole time; only the
        // breath inside it moves. Origin 50% 100%.
        var g = ctx
        origin(&g, 90, 138) {
            $0.translateBy(x: 0, y: 6)
            $0.scaleBy(x: 1.13, y: 0.8)
        }

        // Laboured breath - barely 4%, with a long slow exhale.
        origin(&g, 90, 138) {
            $0.scaleBy(x: kf(t, Unwell.breathScaleX), y: kf(t, Unwell.breathScaleY))
            $0.translateBy(x: 0, y: kf(t, Unwell.breathTy))
        }

        g.fill(mochiBodyPath, with: .color(theme.pet))
        g.fill(mochiHighlightPath, with: .color(theme.pet2.opacity(0.55)))

        // Cheeks flush hot and cool; the right one runs a quarter beat behind.
        drawCheek(&g, cx: 54, t: t)
        drawCheek(&g, cx: 126, t: phase(now, period: 5.6, delay: 0.25))

        // Knotted brows sink with the exhale.
        var brows = g
        brows.opacity = 0.8
        brows.translateBy(x: 0, y: kf(t, Unwell.browTy))
        brows.stroke(unwellBrowLeftPath, with: .color(faceInk), style: unwellBrowStyle)
        brows.stroke(unwellBrowRightPath, with: .color(faceInk), style: unwellBrowStyle)

        // Heavy-lidded eyes - small pupils under lids that sink further on
        // each exhale.
        let ink = GraphicsContext.Shading.color(faceInk)
        g.fill(Path(ellipseIn: CGRect(x: 67, y: 87, width: 10, height: 10)), with: ink)
        g.fill(Path(ellipseIn: CGRect(x: 103, y: 87, width: 10, height: 10)), with: ink)
        var lids = g
        lids.translateBy(x: 0, y: kf(t, Unwell.lidTy))
        drawLid(&lids, x: 64)
        drawLid(&lids, x: 100)

        // Wavy grimace, easing open and closed with the breath. Origin 50% 20%.
        var mouth = g
        origin(&mouth, 90, 108.2) {
            $0.scaleBy(x: kf(t, Unwell.grimaceScaleX), y: kf(t, Unwell.grimaceScaleY))
            $0.translateBy(x: 0, y: kf(t, Unwell.grimaceTy))
        }
        mouth.stroke(unwellGrimacePath, with: ink, style: unwellGrimaceStyle)
    }

    /// One lid: `M x 80 h16 v10 a16 16 0 0 1 -16 0 z` - a pet-colored shade
    /// whose bottom edge bows ~2px down, plus the lash line along that edge.
    /// Both traced once at x = 0 and translated per eye.
    private func drawLid(_ ctx: inout GraphicsContext, x: CGFloat) {
        var g = ctx
        g.translateBy(x: x, y: 0)
        g.fill(unwellLidPath, with: .color(theme.pet))
        g.stroke(unwellLashPath, with: .color(faceInk), style: unwellLashStyle)
    }

    private func drawCheek(_ ctx: inout GraphicsContext, cx: CGFloat, t: CGFloat) {
        var g = ctx
        g.opacity = Double(kf(t, Unwell.flushOpacity))
        origin(&g, cx, 104) {
            let sc = kf(t, Unwell.flushScale)
            $0.scaleBy(x: sc, y: sc)
        }
        g.fill(Path(ellipseIn: CGRect(x: cx - 13, y: 95.5, width: 26, height: 17)), with: .color(theme.petCheek))
    }
}

private let unwellBrowLeftPath: Path = {
    var brow = Path()
    brow.move(to: CGPoint(x: 64, y: 79))
    brow.addCurve(to: CGPoint(x: 80, y: 78), control1: CGPoint(x: 68, y: 74), control2: CGPoint(x: 77, y: 74))
    return brow
}()

private let unwellBrowRightPath: Path = {
    var brow = Path()
    brow.move(to: CGPoint(x: 116, y: 79))
    brow.addCurve(to: CGPoint(x: 100, y: 78), control1: CGPoint(x: 112, y: 74), control2: CGPoint(x: 103, y: 74))
    return brow
}()

private let unwellBrowStyle = StrokeStyle(lineWidth: 3, lineCap: .round)

private let unwellLidPath: Path = {
    var lid = Path()
    lid.move(to: CGPoint(x: 0, y: 80))
    lid.addLine(to: CGPoint(x: 16, y: 80))
    lid.addLine(to: CGPoint(x: 16, y: 90))
    lid.addQuadCurve(to: CGPoint(x: 0, y: 90), control: CGPoint(x: 8, y: 94.3))
    lid.closeSubpath()
    return lid
}()

private let unwellLashPath: Path = {
    var lash = Path()
    lash.move(to: CGPoint(x: 0.5, y: 89.5))
    lash.addCurve(to: CGPoint(x: 16, y: 89.5), control1: CGPoint(x: 4.1, y: 92.1), control2: CGPoint(x: 12.9, y: 92.1))
    return lash
}()

private let unwellLashStyle = StrokeStyle(lineWidth: 2.6, lineCap: .round)

private let unwellGrimacePath: Path = {
    var grimace = Path()
    grimace.move(to: CGPoint(x: 79, y: 112))
    grimace.addCurve(to: CGPoint(x: 93, y: 111), control1: CGPoint(x: 83, y: 105), control2: CGPoint(x: 90, y: 105))
    grimace.addCurve(to: CGPoint(x: 101, y: 111), control1: CGPoint(x: 95, y: 115), control2: CGPoint(x: 99, y: 115))
    return grimace
}()

private let unwellGrimaceStyle = StrokeStyle(lineWidth: 3.2, lineCap: .round)

/// Unwell keyframe tables - everything rides the one 5.6s breath.
private enum Unwell {
    static let breathScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.34, 0.985), (0.46, 0.99), (0.78, 1.02), (1, 1)]
    static let breathScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.34, 1.045), (0.46, 1.03), (0.78, 0.97), (1, 1)]
    static let breathTy: [(CGFloat, CGFloat)] = [(0, 0), (0.34, -2), (0.46, -1), (0.78, 1), (1, 0)]
    static let shadowScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.34, 0.98), (0.78, 1.03), (1, 1)]
    static let shadowOpacity: [(CGFloat, CGFloat)] = [(0, 0.5), (0.34, 0.45), (0.78, 0.54), (1, 0.5)]
    static let lidTy: [(CGFloat, CGFloat)] = [(0, 0), (0.44, 6), (0.68, 7), (1, 0)]
    static let browTy: [(CGFloat, CGFloat)] = [(0, 0), (0.62, 2), (1, 0)]
    static let grimaceScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.34, 0.94), (0.78, 1.08), (1, 1)]
    static let grimaceScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.34, 1.18), (0.78, 0.9), (1, 1)]
    static let grimaceTy: [(CGFloat, CGFloat)] = [(0, 0), (0.34, -1), (0.78, 1), (1, 0)]
    static let flushOpacity: [(CGFloat, CGFloat)] = [(0, 0.3), (0.5, 0.78), (1, 0.3)]
    static let flushScale: [(CGFloat, CGFloat)] = [(0, 1), (0.5, 1.16), (1, 1)]
    /// The comp's whole-svg fever fade animates saturate .4 -> .32, i.e. a
    /// 0.8x dip against its baseline; expressed here as a multiplier so it
    /// composes with the mood saturation MochiPetView applies outside.
    static let fadeSaturation: [(CGFloat, CGFloat)] = [(0, 1), (0.62, 0.8), (1, 1)]
    /// SwiftUI brightness is additive (0 = identity), unlike CSS's
    /// multiplier, so the comp's brightness(.98) dip becomes -0.02.
    static let fadeBrightness: [(CGFloat, CGFloat)] = [(0, 0), (0.62, -0.02), (1, 0)]
}

// MARK: - Sleep idle

/// The out-cold sleep idle, ported 1:1 from the design system's `Mochi Sleep
/// Animation` (dc.html). Real stillness: a static flat-out pose (8% wider,
/// 88% tall, sunk 8px) while a 4.6s snore-breath drives the shadow, the
/// settling lids and the heavy open-mouth breathing; a 9.2s sub-degree slack
/// sway runs out of step with it; three z's drift up on a 1.5s stagger; and
/// every fourth breath (18.4s) he snuggles in - burrows down, two little
/// rubs, settles. Arched-shut lids are the comp's default; the flat-line
/// variant ships default-off and is omitted.
struct SleepIdleCanvas: View {
    var theme: MochiTheme
    var size: CGFloat
    var faceInk: Color
    var paused: Bool = false

    var body: some View {
        // 30fps: "real stillness" by design - a sub-degree sway and a
        // barely-3% breath never need display rate.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, canvasSize: canvasSize, now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size * 170 / 180)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, canvasSize: CGSize, now: Double) {
        let s = canvasSize.width / 180
        ctx.scaleBy(x: s, y: s)

        let t = phase(now, period: 4.6)           // breath, shadow, mouth, lids
        let swayT = phase(now, period: 9.2)
        let nuzzleT = phase(now, period: 18.4)    // every fourth breath

        // Ground shadow - eases with the snore-breath.
        var shadow = ctx
        shadow.opacity = Double(kf(t, Sleep.shadowOpacity))
        origin(&shadow, 90, 150) { $0.scaleBy(x: kf(t, Sleep.shadowScaleX), y: 1) }
        shadow.fill(
            Path(ellipseIn: CGRect(x: 38, y: 141, width: 104, height: 18)),
            with: .color(.black.opacity(0.2))
        )

        // Pose - flat out and settled, held the whole time. Origin 50% 100%.
        var g = ctx
        origin(&g, 90, 138) {
            $0.translateBy(x: 0, y: 8)
            $0.scaleBy(x: 1.08, y: 0.88)
        }

        // Nuzzle - dead still for 11s, then burrow down, two rubs, settle.
        origin(&g, 90, 138) {
            $0.rotate(by: .degrees(Double(kf(nuzzleT, Sleep.nuzzleRot))))
            $0.translateBy(x: kf(nuzzleT, Sleep.nuzzleTx), y: kf(nuzzleT, Sleep.nuzzleTy))
            $0.scaleBy(x: kf(nuzzleT, Sleep.nuzzleScaleX), y: kf(nuzzleT, Sleep.nuzzleScaleY))
        }

        // Sway - well under a degree, out of step with the breath so it
        // reads as slack, not motion.
        origin(&g, 90, 138) {
            $0.rotate(by: .degrees(Double(kf(swayT, Sleep.swayRot))))
        }

        // Snore-breath - barely 3%, slow rise and a longer exhale.
        origin(&g, 90, 138) {
            $0.scaleBy(x: kf(t, Sleep.breathScaleX), y: kf(t, Sleep.breathScaleY))
            $0.translateBy(x: 0, y: kf(t, Sleep.breathTy))
        }

        g.fill(mochiBodyPath, with: .color(theme.pet))
        g.fill(mochiHighlightPath, with: .color(theme.pet2.opacity(0.55)))
        g.fill(Path(ellipseIn: CGRect(x: 42, y: 96.5, width: 24, height: 15)), with: .color(theme.petCheek.opacity(0.8)))
        g.fill(Path(ellipseIn: CGRect(x: 114, y: 96.5, width: 24, height: 15)), with: .color(theme.petCheek.opacity(0.8)))

        // Arched-shut lids and soft brows, settling a touch on the exhale.
        var lids = g
        origin(&lids, 90, 86.5) {
            $0.translateBy(x: 0, y: kf(t, Sleep.lidTy))
            $0.scaleBy(x: 1, y: kf(t, Sleep.lidScaleY))
        }
        lids.stroke(sleepLidLeftPath, with: .color(faceInk), style: sleepLidStyle)
        lids.stroke(sleepLidRightPath, with: .color(faceInk), style: sleepLidStyle)

        var brows = lids
        brows.opacity = 0.45
        brows.stroke(sleepBrowLeftPath, with: .color(faceInk), style: sleepBrowStyle)
        brows.stroke(sleepBrowRightPath, with: .color(faceInk), style: sleepBrowStyle)

        // Heavy mouth breathing - gapes open on the inhale, shrinks almost
        // shut on the exhale. Origin 50% 15%.
        var mouth = g
        origin(&mouth, 90, 111.05) {
            $0.scaleBy(x: kf(t, Sleep.mouthScaleX), y: kf(t, Sleep.mouthScaleY))
        }
        mouth.fill(Path(ellipseIn: CGRect(x: 80.5, y: 108.5, width: 19, height: 17)), with: .color(faceInk.opacity(0.82)))
        mouth.fill(Path(ellipseIn: CGRect(x: 84.5, y: 117.5, width: 11, height: 7)), with: .color(theme.petCheek.opacity(0.5)))

        // Three z's from the same spot, staggered so one is always on its
        // way up and out.
        drawZ(&ctx, t: t)
        drawZ(&ctx, t: phase(now, period: 4.6, delay: 1.5))
        drawZ(&ctx, t: phase(now, period: 4.6, delay: 3))
    }

    private func drawZ(_ ctx: inout GraphicsContext, t: CGFloat) {
        let op = 0.85 * Double(kf(t, Sleep.zOpacity))
        guard op > 0.001 else { return }
        let cx: CGFloat = 137.1, cy: CGFloat = 47.6 // baseline (132, 52), fs 17
        var g = ctx
        g.opacity = op
        origin(&g, cx, cy) {
            $0.translateBy(x: kf(t, Sleep.zTx), y: kf(t, Sleep.zTy))
            let sc = kf(t, Sleep.zScale)
            $0.scaleBy(x: sc, y: sc)
            $0.rotate(by: .degrees(Double(kf(t, Sleep.zRot))))
        }
        g.translateBy(x: cx, y: cy)
        g.scaleBy(x: 17, y: 17)
        g.stroke(zGlyphPath, with: .color(theme.primary), style: zGlyphStyle)
    }
}

private let sleepLidLeftPath: Path = {
    var lid = Path()
    lid.move(to: CGPoint(x: 62, y: 94))
    lid.addCurve(to: CGPoint(x: 79, y: 94), control1: CGPoint(x: 66, y: 86), control2: CGPoint(x: 75, y: 86))
    return lid
}()

private let sleepLidRightPath: Path = {
    var lid = Path()
    lid.move(to: CGPoint(x: 101, y: 94))
    lid.addCurve(to: CGPoint(x: 118, y: 94), control1: CGPoint(x: 105, y: 86), control2: CGPoint(x: 114, y: 86))
    return lid
}()

private let sleepLidStyle = StrokeStyle(lineWidth: 3.4, lineCap: .round)

private let sleepBrowLeftPath: Path = {
    var brow = Path()
    brow.move(to: CGPoint(x: 64, y: 82))
    brow.addCurve(to: CGPoint(x: 79, y: 81), control1: CGPoint(x: 68, y: 78), control2: CGPoint(x: 76, y: 78))
    return brow
}()

private let sleepBrowRightPath: Path = {
    var brow = Path()
    brow.move(to: CGPoint(x: 116, y: 82))
    brow.addCurve(to: CGPoint(x: 101, y: 81), control1: CGPoint(x: 112, y: 78), control2: CGPoint(x: 103, y: 78))
    return brow
}()

private let sleepBrowStyle = StrokeStyle(lineWidth: 2.4, lineCap: .round)

/// Sleep keyframe tables, as fractions of each track's own loop.
private enum Sleep {
    static let breathScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.40, 0.985), (0.48, 0.99), (0.84, 1.022), (1, 1)]
    static let breathScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.40, 1.03), (0.48, 1.025), (0.84, 0.98), (1, 1)]
    static let breathTy: [(CGFloat, CGFloat)] = [(0, 0), (0.40, -2), (0.48, -1.5), (0.84, 1), (1, 0)]
    static let swayRot: [(CGFloat, CGFloat)] = [(0, -0.7), (0.5, 0.7), (1, -0.7)]
    static let shadowScaleX: [(CGFloat, CGFloat)] = [(0, 1), (0.40, 0.98), (0.84, 1.025), (1, 1)]
    static let shadowOpacity: [(CGFloat, CGFloat)] = [(0, 0.5), (0.40, 0.46), (0.84, 0.53), (1, 0.5)]
    static let mouthScaleX: [(CGFloat, CGFloat)] = [(0, 0.62), (0.40, 1), (0.52, 0.98), (0.88, 0.55), (1, 0.62)]
    static let mouthScaleY: [(CGFloat, CGFloat)] = [(0, 0.5), (0.40, 1), (0.52, 0.96), (0.88, 0.4), (1, 0.5)]
    static let lidTy: [(CGFloat, CGFloat)] = [(0, 0), (0.84, 0.8), (1, 0)]
    static let lidScaleY: [(CGFloat, CGFloat)] = [(0, 1), (0.84, 1.06), (1, 1)]
    /// `sl-twitch`: identity until 62%, then the snuggle - burrow, two rubs,
    /// settle by 88%.
    static let nuzzleRot: [(CGFloat, CGFloat)] = [
        (0, 0), (0.62, 0), (0.66, -2), (0.71, 1.8), (0.76, -1.2), (0.82, 0.4), (0.88, 0), (1, 0),
    ]
    static let nuzzleTx: [(CGFloat, CGFloat)] = [
        (0, 0), (0.62, 0), (0.66, -2), (0.71, 2), (0.76, -1.5), (0.82, 0.5), (0.88, 0), (1, 0),
    ]
    static let nuzzleTy: [(CGFloat, CGFloat)] = [
        (0, 0), (0.62, 0), (0.66, 1.5), (0.71, 2), (0.76, 1.5), (0.82, 0.5), (0.88, 0), (1, 0),
    ]
    static let nuzzleScaleX: [(CGFloat, CGFloat)] = [
        (0, 1), (0.62, 1), (0.66, 1.02), (0.71, 1.03), (0.76, 1.02), (0.82, 1), (1, 1),
    ]
    static let nuzzleScaleY: [(CGFloat, CGFloat)] = [
        (0, 1), (0.62, 1), (0.66, 0.98), (0.71, 0.97), (0.76, 0.98), (0.82, 1), (1, 1),
    ]
    static let zOpacity: [(CGFloat, CGFloat)] = [(0, 0), (0.16, 1), (0.62, 0.9), (1, 0)]
    static let zTx: [(CGFloat, CGFloat)] = [(0, 0), (1, 26)]
    static let zTy: [(CGFloat, CGFloat)] = [(0, 6), (1, -46)]
    static let zScale: [(CGFloat, CGFloat)] = [(0, 0.4), (1, 1.5)]
    static let zRot: [(CGFloat, CGFloat)] = [(0, -14), (1, 12)]
}
