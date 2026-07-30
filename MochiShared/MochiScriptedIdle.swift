//
//  MochiScriptedIdle.swift
//  MochiBuddy
//
//  Scripted idle loops ported 1:1 from the design system's `Mochi Idle
//  Thriving` (dc.html). Each mood's idle is a single choreographed beat, not a
//  pile of random loops: `MochiIdleScript` holds the keyframe tables and
//  `ScriptedIdleCanvas` plays them. The nested GraphicsContext transforms
//  mirror the SVG's nested <g> groups (lean > breathe > gaze > {blink eyes,
//  mouth}); transform-origins are applied as translate-in / transform /
//  translate-out, exactly like CSS `transform-origin`.
//
//  - Thriving: a lively 12s beat - peeks left/right, then a pleased wiggle
//    (hop, mouth-open, happy squint) with a heart floating up and the shadow
//    reacting. Sparkles twinkle throughout.
//  - Content: a calmer 18s beat - slow breaths, the odd single blink, a look
//    left and a little pootle right. No sparkles, no heart, static shadow.
//  - Tired: ported from `Mochi Tired Animation` (dc.html). Unlike the other
//    two it is not one beat but decoupled loops, exactly like its CSS: a 7.2s
//    nod, 3.6s breath/shadow/mouth, a 6s heavy-lidded lazy blink, sweat drips
//    half a loop apart and three staggered drifting z's. `TiredIdleCanvas`
//    samples each loop against its own period off the shared clock.
//

import SwiftUI

/// One mood's idle, as fractions of its own loop (0...1). The design's springy
/// overshoot lives in the stop values themselves, so eased interpolation
/// between them reproduces the feel without hand-coding each cubic-bezier.
struct MochiIdleScript {
    enum Face { case thriving, content }

    var beat: Double            // full loop length (s)
    var breathBeat: Double      // breath's own sub-loop (s)
    var breatheDepth: CGFloat   // peak squash, e.g. 0.035
    var face: Face
    var decorated: Bool         // sparkles + floating heart
    var animatesShadow: Bool
    var shadowAlpha: Double

    var leanRot, leanTx, leanTy, leanScaleX, leanScaleY: [(CGFloat, CGFloat)]
    var gazeTx, gazeTy, blink: [(CGFloat, CGFloat)]
    var mouthScaleX, mouthScaleY: [(CGFloat, CGFloat)]
    var shadowScaleX, shadowOpacity: [(CGFloat, CGFloat)]

    var cheekLeft: CGRect
    var cheekRight: CGRect
    var cheekOpacity: Double

    static let identity: [(CGFloat, CGFloat)] = [(0, 1), (1, 1)]
    static let flat: [(CGFloat, CGFloat)] = [(0, 0), (1, 0)]
}

struct ScriptedIdleCanvas: View {
    var theme: MochiTheme
    var size: CGFloat
    var faceInk: Color
    var showsSparkles: Bool = true
    var script: MochiIdleScript

    private let twinkleBeat: Double = 1.9

    var body: some View {
        TimelineView(.animation) { timeline in
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

        let t = CGFloat(now.truncatingRemainder(dividingBy: script.beat) / script.beat)
        let bt = now.truncatingRemainder(dividingBy: script.breathBeat) / script.breathBeat

        // Ground shadow - reacts to the hop when the script animates it.
        var shadow = ctx
        shadow.opacity = script.animatesShadow ? Double(kf(t, script.shadowOpacity)) : 1
        origin(&shadow, 90, 150) {
            if script.animatesShadow { $0.scaleBy(x: kf(t, script.shadowScaleX), y: 1) }
        }
        shadow.fill(
            Path(ellipseIn: CGRect(x: 40, y: 141, width: 100, height: 18)),
            with: .color(.black.opacity(script.shadowAlpha))
        )

        // Lean - whole-body sway (+ closing wiggle). Origin 90,140.
        var lean = ctx
        origin(&lean, 90, 140) {
            $0.rotate(by: .degrees(Double(kf(t, script.leanRot))))
            $0.translateBy(x: kf(t, script.leanTx), y: kf(t, script.leanTy))
            $0.scaleBy(x: kf(t, script.leanScaleX), y: kf(t, script.leanScaleY))
        }

        // Breathe - gentle squash, inside the lean. Origin 90,140.
        let bph = CGFloat((1 - cos(2 * .pi * bt)) / 2)
        var body = lean
        origin(&body, 90, 140) {
            $0.scaleBy(x: 1 + script.breatheDepth * bph, y: 1 - script.breatheDepth * bph)
        }
        drawBody(&body)

        // Gaze - the face peeks (pure translate, so origin is moot).
        var face = body
        face.translateBy(x: kf(t, script.gazeTx), y: kf(t, script.gazeTy))

        // Eyes with the blink squeeze. Origin 90,88.
        var eyes = face
        origin(&eyes, 90, 88) { $0.scaleBy(x: 1, y: kf(t, script.blink)) }
        drawEyes(&eyes)

        // Mouth - opens on the thriving wiggle; identity (no-op) for content.
        var mouth = face
        origin(&mouth, 90, 104) {
            $0.scaleBy(x: kf(t, script.mouthScaleX), y: kf(t, script.mouthScaleY))
        }
        drawMouth(&mouth)

        // Sparkles + floating heart (thriving only).
        if script.decorated {
            if showsSparkles {
                drawSparkle(&ctx, cx: 40, cy: 68, r: 7, color: theme.primary, phase: twinklePhase(now, 0))
                drawSparkle(&ctx, cx: 143, cy: 72, r: 5.6, color: theme.accent2, phase: twinklePhase(now, 0.45))
                drawSparkle(&ctx, cx: 32, cy: 102, r: 4.2, color: theme.accent2, phase: twinklePhase(now, 0.9))
            }
            drawFloatingHeart(&ctx, t: t)
        }
    }

    // MARK: - Art

    private func drawBody(_ ctx: inout GraphicsContext) {
        ctx.fill(mochiBodyPath, with: .color(theme.pet))
        ctx.fill(mochiHighlightPath, with: .color(theme.pet2.opacity(0.55)))

        ctx.fill(Path(ellipseIn: script.cheekLeft), with: .color(theme.petCheek.opacity(script.cheekOpacity)))
        ctx.fill(Path(ellipseIn: script.cheekRight), with: .color(theme.petCheek.opacity(script.cheekOpacity)))
    }

    private func drawEyes(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(faceInk)
        switch script.face {
        case .thriving:
            ctx.fill(Path(ellipseIn: CGRect(x: 62.5, y: 79, width: 15, height: 18)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 102.5, y: 79, width: 15, height: 18)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 70, y: 82, width: 5.2, height: 5.2)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 110, y: 82, width: 5.2, height: 5.2)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 66.3, y: 90.1, width: 2.6, height: 2.6)), with: .color(.white.opacity(0.8)))
            ctx.fill(Path(ellipseIn: CGRect(x: 106.3, y: 90.1, width: 2.6, height: 2.6)), with: .color(.white.opacity(0.8)))
        case .content:
            ctx.fill(Path(ellipseIn: CGRect(x: 66, y: 82, width: 12, height: 12)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 102, y: 82, width: 12, height: 12)), with: ink)
            ctx.fill(Path(ellipseIn: CGRect(x: 72, y: 84, width: 4, height: 4)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 108, y: 84, width: 4, height: 4)), with: .color(.white))
        }
    }

    private func drawMouth(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(faceInk)
        switch script.face {
        case .thriving:
            var smile = Path()
            smile.move(to: CGPoint(x: 80, y: 103))
            smile.addCurve(to: CGPoint(x: 100, y: 103), control1: CGPoint(x: 84.5, y: 110.5), control2: CGPoint(x: 95.5, y: 110.5))
            ctx.stroke(smile, with: ink, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

            var tongue = Path()
            tongue.move(to: CGPoint(x: 86.5, y: 108.5))
            tongue.addCurve(to: CGPoint(x: 94, y: 108.5), control1: CGPoint(x: 89, y: 111.5), control2: CGPoint(x: 92, y: 111.5))
            tongue.closeSubpath()
            ctx.fill(tongue, with: .color(theme.petCheek.opacity(0.9)))
        case .content:
            var smile = Path()
            smile.move(to: CGPoint(x: 80, y: 104))
            smile.addCurve(to: CGPoint(x: 100, y: 104), control1: CGPoint(x: 84, y: 109), control2: CGPoint(x: 96, y: 109))
            ctx.stroke(smile, with: ink, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        }
    }

    private func drawSparkle(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, color: Color, phase: Double) {
        let tw = (1 - cos(2 * .pi * phase)) / 2 // 0 -> 1 -> 0
        var g = ctx
        g.opacity = 0.25 + 0.75 * tw
        origin(&g, cx, cy) {
            $0.rotate(by: .degrees(12 * tw))
            $0.scaleBy(x: 0.75 + 0.45 * tw, y: 0.75 + 0.45 * tw)
        }
        g.fill(starPath(cx: cx, cy: cy, r: r), with: .color(color))
    }

    private func drawFloatingHeart(_ ctx: inout GraphicsContext, t: CGFloat) {
        let op = Double(kf(t, Hearts.opacity))
        guard op > 0.001 else { return }
        var g = ctx
        g.opacity = op
        g.translateBy(x: 152, y: 104)
        g.translateBy(x: kf(t, Hearts.tx), y: kf(t, Hearts.ty))
        g.scaleBy(x: kf(t, Hearts.scale), y: kf(t, Hearts.scale))
        g.translateBy(x: -152, y: -104)
        g.fill(heartPath(), with: .color(theme.primary))
    }

    // MARK: - Helpers

    private func twinklePhase(_ now: Double, _ delay: Double) -> Double {
        var p = (now - delay).truncatingRemainder(dividingBy: twinkleBeat) / twinkleBeat
        if p < 0 { p += 1 }
        return p
    }

    private func starPath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        let w: CGFloat = 0.32 // pinched waist
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addLine(to: CGPoint(x: cx + r * w, y: cy - r * w))
        p.addLine(to: CGPoint(x: cx + r, y: cy))
        p.addLine(to: CGPoint(x: cx + r * w, y: cy + r * w))
        p.addLine(to: CGPoint(x: cx, y: cy + r))
        p.addLine(to: CGPoint(x: cx - r * w, y: cy + r * w))
        p.addLine(to: CGPoint(x: cx - r, y: cy))
        p.addLine(to: CGPoint(x: cx - r * w, y: cy - r * w))
        p.closeSubpath()
        return p
    }

    private func heartPath() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 152, y: 100))
        p.addCurve(to: CGPoint(x: 159, y: 102.4), control1: CGPoint(x: 154.6, y: 96.8), control2: CGPoint(x: 159, y: 98.8))
        p.addCurve(to: CGPoint(x: 152, y: 110.8), control1: CGPoint(x: 159, y: 105.8), control2: CGPoint(x: 154.6, y: 108.4))
        p.addCurve(to: CGPoint(x: 145, y: 102.4), control1: CGPoint(x: 149.4, y: 108.4), control2: CGPoint(x: 145, y: 105.8))
        p.addCurve(to: CGPoint(x: 152, y: 100), control1: CGPoint(x: 145, y: 98.8), control2: CGPoint(x: 149.4, y: 96.8))
        p.closeSubpath()
        return p
    }

}

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

/// Applies a transform about (ox, oy), matching CSS `transform-origin`.
private func origin(_ ctx: inout GraphicsContext, _ ox: CGFloat, _ oy: CGFloat, _ body: (inout GraphicsContext) -> Void) {
    ctx.translateBy(x: ox, y: oy)
    body(&ctx)
    ctx.translateBy(x: -ox, y: -oy)
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

/// Floating-heart keyframes (thriving only), shared by the canvas.
private enum Hearts {
    static let opacity: [(CGFloat, CGFloat)] = [(0, 0), (0.78, 0), (0.84, 1), (0.96, 0), (1, 0)]
    static let tx: [(CGFloat, CGFloat)] = [(0, 0), (0.78, 0), (0.84, 2), (0.96, 8), (1, 8)]
    static let ty: [(CGFloat, CGFloat)] = [(0, 0), (0.78, 0), (0.84, -14), (0.96, -34), (1, -34)]
    static let scale: [(CGFloat, CGFloat)] = [(0, 0.4), (0.78, 0.4), (0.84, 1), (0.96, 0.85), (1, 0.85)]
}

// MARK: - Mood scripts

extension MochiIdleScript {
    /// The lively 12s thriving beat.
    static let thriving = MochiIdleScript(
        beat: 12, breathBeat: 3.4, breatheDepth: 0.035, face: .thriving,
        decorated: true, animatesShadow: true, shadowAlpha: 0.10,
        leanRot: [
            (0, 0), (0.26, 0), (0.33, -4.5), (0.42, -4.5), (0.50, 0), (0.55, 0),
            (0.61, 4.5), (0.69, 4.5), (0.76, 0), (0.79, 0),
            (0.83, -7), (0.87, 6), (0.91, -3.5), (0.95, 1.5), (1, 0),
        ],
        leanTx: [
            (0, 0), (0.26, 0), (0.33, -3), (0.42, -3), (0.50, 0), (0.55, 0),
            (0.61, 3), (0.69, 3), (0.76, 0), (1, 0),
        ],
        leanTy: [(0, 0), (0.79, 0), (0.83, -7), (0.87, -2), (0.91, 0), (1, 0)],
        leanScaleX: [(0, 1), (0.79, 1), (0.83, 1.05), (0.91, 1), (1, 1)],
        leanScaleY: [(0, 1), (0.79, 1), (0.83, 0.94), (0.91, 1), (1, 1)],
        gazeTx: [
            (0, 0), (0.28, 0), (0.33, -7), (0.43, -7), (0.50, 0), (0.56, 0),
            (0.61, 7), (0.70, 7), (0.76, 0), (1, 0),
        ],
        gazeTy: [
            (0, 0), (0.28, 0), (0.33, 1), (0.43, 1), (0.50, 0), (0.56, 0),
            (0.61, 1), (0.70, 1), (0.76, 0), (1, 0),
        ],
        blink: [
            (0, 1), (0.135, 1), (0.148, 0.08), (0.162, 1), (0.18, 1), (0.193, 0.08),
            (0.206, 1), (0.55, 1), (0.564, 0.08), (0.578, 1), (0.80, 1),
            (0.83, 0.3), (0.92, 0.3), (0.95, 1), (1, 1),
        ],
        mouthScaleX: [(0, 1), (0.79, 1), (0.84, 1.12), (0.91, 1.12), (0.96, 1), (1, 1)],
        mouthScaleY: [(0, 1), (0.79, 1), (0.84, 1.35), (0.91, 1.35), (0.96, 1), (1, 1)],
        shadowScaleX: [(0, 1), (0.79, 1), (0.84, 0.86), (0.92, 1), (1, 1)],
        shadowOpacity: [(0, 1), (0.79, 1), (0.84, 0.7), (0.92, 1), (1, 1)],
        cheekLeft: CGRect(x: 45, y: 94, width: 22, height: 16),
        cheekRight: CGRect(x: 113, y: 94, width: 22, height: 16),
        cheekOpacity: 0.55
    )

    /// The calmer 18s content beat - no wiggle, no sparkles, no heart.
    static let content = MochiIdleScript(
        beat: 18, breathBeat: 4.6, breatheDepth: 0.02, face: .content,
        decorated: false, animatesShadow: false, shadowAlpha: 0.09,
        leanRot: [
            (0, 0), (0.30, 0), (0.38, -3), (0.46, -3), (0.56, 0), (0.70, 0),
            (0.78, 2.5), (0.86, 1.5), (0.92, 1.5), (1, 0),
        ],
        leanTx: [
            (0, 0), (0.30, 0), (0.38, -2), (0.46, -2), (0.56, 0), (0.70, 0),
            (0.78, 2), (0.86, 1), (0.92, 1), (1, 0),
        ],
        leanTy: [(0, 0), (0.70, 0), (0.78, 1), (0.86, 0), (1, 0)],
        leanScaleX: [(0, 1), (0.70, 1), (0.78, 1.02), (0.86, 1), (1, 1)],
        leanScaleY: [(0, 1), (0.70, 1), (0.78, 0.97), (0.86, 1), (1, 1)],
        gazeTx: [
            (0, 0), (0.32, 0), (0.39, -5), (0.47, -5), (0.56, 0), (0.76, 0),
            (0.80, 3), (0.88, 3), (0.95, 0), (1, 0),
        ],
        gazeTy: [
            (0, 0), (0.32, 0), (0.39, 1), (0.47, 1), (0.56, 0), (0.76, 0),
            (0.80, 2), (0.88, 2), (0.95, 0), (1, 0),
        ],
        blink: [
            (0, 1), (0.21, 1), (0.224, 0.08), (0.238, 1), (0.61, 1), (0.624, 0.08),
            (0.638, 1), (0.77, 1), (0.80, 0.55), (0.87, 0.55), (0.91, 1), (1, 1),
        ],
        mouthScaleX: MochiIdleScript.identity,
        mouthScaleY: MochiIdleScript.identity,
        shadowScaleX: MochiIdleScript.identity,
        shadowOpacity: MochiIdleScript.identity,
        cheekLeft: CGRect(x: 46, y: 95, width: 20, height: 14),
        cheekRight: CGRect(x: 114, y: 95, width: 20, height: 14),
        cheekOpacity: 0.4
    )
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

    var body: some View {
        TimelineView(.animation) { timeline in
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
        var lip = Path()
        lip.move(to: CGPoint(x: 84, y: 107))
        lip.addCurve(to: CGPoint(x: 94.4, y: 107), control1: CGPoint(x: 86.4, y: 109.6), control2: CGPoint(x: 92, y: 109.6))
        mouth.stroke(lip, with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))

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
    private func drawLid(_ ctx: inout GraphicsContext, x: CGFloat) {
        var lid = Path()
        lid.move(to: CGPoint(x: x, y: 68))
        lid.addLine(to: CGPoint(x: x + 22, y: 68))
        lid.addLine(to: CGPoint(x: x + 22, y: 84))
        lid.addQuadCurve(to: CGPoint(x: x, y: 84), control: CGPoint(x: x + 11, y: 89.9))
        lid.closeSubpath()
        ctx.fill(lid, with: .color(theme.pet))

        var lash = Path()
        lash.move(to: CGPoint(x: x + 0.5, y: 84))
        lash.addCurve(to: CGPoint(x: x + 21.5, y: 84), control1: CGPoint(x: x + 5, y: 87.4), control2: CGPoint(x: x + 17.5, y: 87.4))
        ctx.stroke(lash, with: .color(faceInk), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
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
        var drop = Path()
        drop.move(to: CGPoint(x: x, y: y))
        drop.addCurve(
            to: CGPoint(x: x, y: y + 11),
            control1: CGPoint(x: x + 4, y: y + 6),
            control2: CGPoint(x: x + 4, y: y + 11)
        )
        drop.addCurve(
            to: CGPoint(x: x, y: y),
            control1: CGPoint(x: x - 4, y: y + 11),
            control2: CGPoint(x: x - 4, y: y + 6)
        )
        drop.closeSubpath()
        g.fill(drop, with: .color(Color(hex: 0x8FD3F4)))
    }

    /// One drifting z. The SVG anchors text at the baseline start; Canvas
    /// anchors at center, so the glyph center is estimated from the font size.
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
        g.draw(
            Text("z")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primary),
            at: CGPoint(x: cx, y: cy)
        )
    }

    /// Position within a looping animation of `period` seconds, 0...1.
    private func phase(_ now: Double, period: Double, delay: Double = 0) -> CGFloat {
        var p = (now - delay).truncatingRemainder(dividingBy: period) / period
        if p < 0 { p += 1 }
        return CGFloat(p)
    }

    /// Eased 0 -> 1 -> 0 over one period - what the CSS's symmetric
    /// 0/50/100% keyframes with sine-ish easing produce.
    private func wave(_ now: Double, period: Double) -> CGFloat {
        CGFloat((1 - cos(2 * .pi * Double(phase(now, period: period)))) / 2)
    }
}

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
