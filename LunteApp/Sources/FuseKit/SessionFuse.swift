import SwiftUI

/// A session's fuse in a pill, ash and all, drawn by the menu bar fuse itself: the fuse it ended with, as long or as
/// short, as tight or as loose as the lunte would be, what cool grew still green at its start, and what its worst burn
/// took as dots past its tip. A Boom leaves a blast mark: scorch where the fuse began, soot streaks, and the ash flung
/// wide. `replay` runs the session back, from a fresh fuse at 0, with the menu bar's own feeds, burns and bang, and
/// settles on the pill at rest at 1.
// Why: heat burns the tip and cool feeds the start (docs/why.md#burn-tip-feed-start)
public struct SessionFuse: View, Animatable {
    let levels: [Double] // the fuse line, in order, 0...`FuseScene.full`
    let boomed: Bool
    public var replay: Double
    public var animatableData: Double { get { replay } set { replay = newValue } }
    let green: Bool // ponytail: the lab's neutral alternative; goes once one is picked
    @Environment(\.colorScheme) private var scheme
    static let zoom = 1.2, pad = 7.0

    public init(levels: [Double], boomed: Bool, replay: Double = 1, green: Bool = true) {
        self.levels = levels; self.boomed = boomed; self.replay = replay; self.green = green
    }

    /// How long the replay takes on screen: as long as the fuse's moves, up to 3 seconds, then faster.
    public static func duration(_ levels: [Double], boomed: Bool) -> Double { min(3, Replay(levels, boomed: boomed).end) }

    public var body: some View {
        Canvas { context, size in
            let dark = scheme == .dark, ink = dark ? CGColor(gray: 1, alpha: 0.85) : FuseScene.ink
            let play = Replay(levels, boomed: boomed), end = play.end
            let settle = replay > 0.99 ? 1 : max(0, (replay - 0.9) / 0.1) // the last tenth lets the flame and sparks fade
            let seed = Int(levels.reduce(0, +) * 1000) &+ levels.count
            context.withCGContext { ctx in
                // The fuse's own coordinates, its start a pad in from the left.
                ctx.translateBy(x: Self.pad + (3.3 - FuseScene.start) * Self.zoom, y: size.height / 2 + 9.5 * Self.zoom)
                ctx.scaleBy(x: Self.zoom, y: -Self.zoom)
                let right = (size.width - 2 * Self.pad) / Self.zoom - (3.3 - FuseScene.start)
                // The replay at `t`, or, long after its end, the pill at rest: the same fuse, every flame out. A Boom
                // rests as its blast mark, before the menu bar's word would come in.
                let frame = { (t: Double, alpha: Double) in
                    let scene = play.scene(at: t), left = scene.length(t), burnt = max(0, play.start + play.fed(at: t) - left)
                    let blast = play.bang.map { min(1, max(0, (t - $0) / 0.35)) } ?? 0 // it comes in as the flash goes
                    if blast > 0 { Self.blast(ctx, amount: burnt, seed: seed, dark: dark, ink: ink, alpha: alpha * blast) }
                    ctx.setAlpha(alpha * (1 - blast))
                    Self.ash(ctx, after: left, amount: burnt, right: right, ink: ink)
                    ctx.setAlpha(alpha)
                    guard left > 0.002 || t <= end else { return }
                    scene.draw(ctx, at: t, ink: ink)
                    // What cool grew past a fresh fuse stays green at the start, where it was fed in.
                    if green, left > 1.005 { scene.stroke(ctx, scene.head.value(t), scene.head.value(t) + left - 1, t, Palette.green, width: 1.5) }
                }
                if settle > 0 { frame(boomed ? end + 1e6 : end + 20, 1) }
                if settle < 1 { frame(min(end, replay / 0.9 * end), 1 - settle) } // over the rest, so it never dims
            }
        }
        .frame(width: 64, height: 26)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    /// What burnt, as dots on a coil running on from the tip of a fuse `left` long, as loose as the lunte's at first and
    /// squeezed tighter once there's more than fits before `right`.
    static func ash(_ ctx: CGContext, after left: Double, amount: Double, right: Double, ink: CGColor) {
        guard amount > 0.005 else { return }
        let full = FuseScene.full, share = min(1, left / full)
        let tip = FuseScene.start + FuseScene.pitch * (1 + FuseScene.stretch * (1 - share)) * share + 2
        let natural = FuseScene.pitch / full, pitch = min(natural, max(2, right - tip) / amount)
        let r = FuseScene.radius, rx = min(r, pitch * full / 3 * 0.62), n = max(2, Int(amount * 200))
        ctx.saveGState()
        ctx.beginPath()
        for i in 0...n {
            let a = amount * Double(i) / Double(n), angle = 6 * .pi * (left + a) / full
            let p = CGPoint(x: tip + pitch * a + rx * sin(angle), y: 9.5 - r * cos(angle))
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.setStrokeColor(ink.copy(alpha: ink.alpha * 0.3)!)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [0.01, 2 + 1.5 * (1 - pitch / natural)])
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A Boom's mark, where the fuse began: scorch, darkest in the middle and ragged at the edge, soot streaks thrown out
    /// from it, and what burnt flung wide as debris. The same session always leaves the same mark.
    static func blast(_ ctx: CGContext, amount: Double, seed: Int, dark: Bool, ink: CGColor, alpha: Double) {
        let c = CGPoint(x: FuseScene.start + 8, y: 9.5) // a little in, so the whole blast lands inside the pill
        let random = { (i: Int, k: Int) -> Double in
            let x = sin(Double(seed &* 7919 &+ i &* 127 &+ k &* 311) * 12.9898) * 43758.5453
            return x - x.rounded(.down)
        }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        // Scorch: a few soft blobs, so its edge isn't a circle.
        let colours = [CGColor(gray: 0, alpha: dark ? 0.65 : 0.5), Palette.soot.copy(alpha: dark ? 0.4 : 0.28)!, Palette.soot.copy(alpha: 0)!]
        let scorch = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: [0, 0.55, 1])!
        for i in 0..<5 {
            let at = CGPoint(x: c.x + 14 * random(i, 1) - 3, y: c.y + 4 * random(i, 2) - 2)
            ctx.drawRadialGradient(scorch, startCenter: at, startRadius: 0, endCenter: at, endRadius: 6 + 6 * random(i, 3), options: [])
        }
        // Streaks, thrown out along the pill.
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: dark ? 0.55 : 0.32))
        for i in 0..<11 {
            let a = 2 * .pi * (Double(i) + 0.6 * random(i, 4)) / 11, reach = 7 + 12 * random(i, 5)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: c.x + 2.5 * cos(a), y: c.y + 2.5 * sin(a)))
            ctx.addLine(to: CGPoint(x: c.x + reach * 1.5 * cos(a), y: c.y + reach * 0.6 * sin(a)))
            ctx.setLineWidth(0.5 + 0.6 * random(i, 6))
            ctx.strokePath()
        }
        // Debris: the ash, flung wide, more the more burnt.
        for i in 0..<Int(16 + 12 * amount) {
            let a = 2 * .pi * random(i, 7), d = 3 + 26 * pow(random(i, 8), 0.8), r = 0.35 + 0.35 * random(i, 9)
            let p = CGPoint(x: c.x + d * cos(a) * 1.3, y: c.y + min(8, d * 0.45) * sin(a))
            ctx.setFillColor(ink.copy(alpha: ink.alpha * (0.25 + 0.25 * random(i, 10)))!)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
        ctx.restoreGState()
    }
}

/// The session as the menu bar showed it, each move given as long as the fuse takes to make it, in at most three: fed
/// up to its high, burnt down to its low, and fed on to how it ended, in the order they happened. A dip that stays at
/// 85 % or more is a scratch, not a burn, and isn't shown. A Boom is fed to its peak, burnt to where it caught, then
/// the race, the silence and the bang.
// Why: the peak-end rule, and the words and the bars use the same thresholds (docs/why.md#session-story)
struct Replay {
    let start: Double
    var steps: [(at: Double, look: FuseLook)] = []
    var grows: [(at: Double, mend: Double)] = []
    var bang: Double?
    var end = 0.0

    init(_ levels: [Double], boomed: Bool) {
        start = levels.first ?? 1
        let last = levels.last ?? start, low = levels.indices.min { levels[$0] < levels[$1] } ?? 0
        let moves = boomed ? [levels.max() ?? 1, levels.dropLast().last ?? start, 0]
            : levels[low] < 0.85 ? [levels[...low].max() ?? start, levels[low], last] : last > start ? [last] : []
        var t = 0.15, now = start
        for l in moves where abs(l - now) > 0.01 {
            if boomed, l < 0.001 {
                steps.append((t, FuseLook(phase: .fusing, left: 0)))
                t += FuseScene.raceFor + 0.5
                steps.append((t, FuseLook(phase: .blown, left: 0)))
                bang = t
                end = t + 1.3
                return
            }
            steps.append((t, FuseLook(left: l)))
            if l > now {
                grows.append((t, l - now))
                t += 1 + 0.8 * (l - now) // the feed, and a beat
            } else {
                // The burn: quick, then a crawl through the last third, as `FuseScene.burn` times it.
                let fast = max(0, now - max(l, 1.0 / 3)), crawl = max(0, min(now, 1.0 / 3) - l)
                t += 0.25 + max(0.3, (fast > 0 ? 0.45 + 0.75 * fast : 0) + (crawl > 0 ? 1.2 + 9 * crawl : 0))
            }
            now = l
        }
        end = t + 0.3
    }

    func scene(at t: Double) -> FuseScene {
        var scene = FuseScene()
        scene.update(FuseLook(left: start), at: -10, animated: false)
        for s in steps where s.at <= t { scene.update(s.look, at: s.at) }
        return scene
    }

    /// The fuse fed in by `t`, as the scene feeds it.
    func fed(at t: Double) -> Double {
        grows.reduce(0) { $0 + $1.mend * Ease.inOutCubic(min(1, max(0, (t - $1.at) / (0.8 + 0.8 * $1.mend)))) }
    }
}
