import SwiftUI

/// A session's fuse in a pill, drawn by the menu bar fuse itself, as one coil: the fuse it ended with, what cool grew
/// still green at its start, and what burnt as dots, right where the flame turned it to ash. The ash holds the coil's
/// shape, so it's as tight as all the fuse the session was ever fed: the more, the tighter, squeezed up to fit the pill,
/// and past the tightest it goes, trailing off its end. A Boom leaves a blast mark where the fuse began, with the ash
/// flung out of it. `replay` runs the session back, from a fresh fuse at 0, with the menu bar's own feeds, burns and
/// bang, and settles on the pill at rest at 1. With `breeze`, once the pointer settles on its row, a breeze runs through
/// it, as while a prompt is rated, stirring the ash and fanning the embers.
// Why: heat burns the tip and cool feeds the start (docs/why.md#burn-tip-feed-start)
public struct SessionFuse: View, Animatable {
    let levels: [Double] // the fuse line, in order, 0...`FuseScene.full`
    let boomed: Bool
    public var replay: Double
    public var animatableData: Double { get { replay } set { replay = newValue } }
    let green: Bool // ponytail: the lab's neutral alternative; goes once one is picked
    let breeze: Bool
    let gustAt: Double? // ponytail: the lab's moment into a breeze, for its stills
    let fixed: Double? // this wide, or nil to fill its frame, every part to scale, so it can grow open
    @State private var hover: (on: Date, off: Date?)?
    @State private var settled: Date? // when the pointer came onto its row
    @Environment(\.colorScheme) private var scheme
    public static let width = 64.0
    static let zoom = 1.2, pad = 7.0
    static let room = (width - 2 * pad) / zoom - 3.3 - FuseScene.radius - 1 // how far the coil can reach inside the pill
    static let ground = CGPoint(x: FuseScene.start + 7, y: 9.5) // where a Boom leaves its mark: a little in, to fit

    public init(levels: [Double], boomed: Bool, replay: Double = 1, green: Bool = true, breeze: Bool = false, gustAt: Double? = nil,
                width: Double? = 64) {
        self.levels = levels; self.boomed = boomed; self.replay = replay; self.green = green; self.breeze = breeze; self.gustAt = gustAt
        fixed = width
    }

    /// How long the replay takes on screen: as long as the fuse's moves, up to 4 seconds, then faster.
    public static func duration(_ levels: [Double], boomed: Bool) -> Double { min(4, Replay.of(levels, boomed: boomed).end) }

    /// The moment of the session (along `times`, the fuse line's) that `replay` shows, and back, so a hairline over the
    /// session's clock and the pill line up exactly: at the turns, and evenly in time between them, as each step plays
    /// the stretch from the turn before it to its own. A Boom's prompt comes with the bang, not after the blast settles.
    public static func moment(at replay: Double, _ levels: [Double], _ times: [Double], boomed: Bool) -> Double {
        let play = Replay.of(levels, boomed: boomed), t = min(play.end, replay / 0.9 * play.end)
        guard let first = times.first, let k = play.spans.lastIndex(where: { $0.at <= t }) else { return times.first ?? 0 }
        let s = play.spans[k], next = k + 1 < play.spans.count ? play.spans[k + 1].at : play.bang ?? play.end
        let a = times[min(s.from, times.count - 1)], b = times[min(s.to, times.count - 1)]
        return times.count > 1 ? a + (b - a) * min(1, (t - s.at) / max(0.01, next - s.at)) : first
    }

    public static func replay(at moment: Double, _ levels: [Double], _ times: [Double], boomed: Bool) -> Double {
        let play = Replay.of(levels, boomed: boomed), at = { (i: Int) in times[min(i, times.count - 1)] }
        guard !times.isEmpty, let k = play.spans.lastIndex(where: { at($0.from) <= moment }) else { return 0 }
        let s = play.spans[k], next = k + 1 < play.spans.count ? play.spans[k + 1].at : play.bang ?? play.end
        if k == play.spans.count - 1, moment >= at(s.to) { return 1 }
        let t = s.at + (next - s.at) * min(1, (moment - at(s.from)) / max(1, at(s.to) - at(s.from)))
        return min(0.9, t / play.end * 0.9)
    }

    public var body: some View {
        TimelineView(.animation(paused: hover == nil)) { timeline in
            // How far into the breeze, and when it began to drop, in seconds.
            let gust = gustAt.map { (in: $0, off: nil as Double?) }
                ?? hover.map { h in (in: timeline.date.timeIntervalSince(h.on), off: h.off?.timeIntervalSince(h.on)) }
            Canvas { context, size in draw(context, size, gust: gust) }
        }
        .aspectRatio(Self.width / 26, contentMode: .fit)
        .frame(width: fixed.map { CGFloat($0) }, height: fixed.map { CGFloat($0 * 26 / Self.width) })
        .background(Color.primary.opacity(0.08), in: Capsule())
        .clipShape(Capsule())
        .onChange(of: breeze) { _, on in
            let now = Date()
            settled = on ? now : nil
            // Only once the pointer settles on its row, so the rows it crosses as a list scrolls stay still.
            if on { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if settled == now { hover = (Date(), nil) } } } else if let h = hover {
                hover = (h.on, now)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if hover?.off == now { hover = nil } } // once it's dropped
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, gust: (in: Double, off: Double?)?) {
        let dark = scheme == .dark, ink = dark ? CGColor(gray: 1, alpha: 0.85) : FuseScene.ink
        let play = Replay.of(levels, boomed: boomed), end = play.end, rest = end + 20
        let settle = replay > 0.99 ? 1 : max(0, (replay - 0.9) / 0.1) // the last tenth lets the flame and sparks fade
        let seed = Int(levels.reduce(0, +) * 1000) &+ levels.count
        let k = size.width / Self.width // drawn bigger as the pill is, every part to scale
        context.withCGContext { ctx in
            // The fuse's own coordinates, its start a pad in from the left.
            ctx.translateBy(x: (Self.pad + (3.3 - FuseScene.start) * Self.zoom) * k, y: size.height / 2 + 9.5 * Self.zoom * k)
            ctx.scaleBy(x: Self.zoom * k, y: -Self.zoom * k)
            // The replay at `t`, or, long after its end, the pill at rest: the same fuse, every flame out, and a Boom
            // only its mark, before the menu bar's word would come in.
            let frame = { (t: Double, alpha: Double, wind: (on: Double, off: Double?)?) in
                let scene = play.scene(at: t, wind: wind), blow = wind.map { Self.blow(t, on: $0.on, off: $0.off) } ?? 0
                let left = scene.length(t), head = scene.head.value(t)
                ctx.setAlpha(alpha)
                if let bang = play.bang, t > bang { Self.blast(ctx, since: t - bang, seed: seed, ink: ink, blow: blow, t: t) }
                Self.ash(ctx, play, scene, t, ink: ink, blow: blow)
                guard left > 0.002 || t <= end else { return }
                scene.draw(ctx, at: t, ink: ink)
                // What cool grew past a fresh fuse stays green at the start, where it was fed in.
                if green, left > 1.005 { scene.stroke(ctx, head, head + left - 1, t, Palette.green, width: 1.5) }
            }
            if settle > 0 { frame(rest + (gust?.in ?? 0), 1, gust.map { (rest, $0.off.map { rest + $0 }) }) }
            if settle < 1 { frame(min(end, replay / 0.9 * end), 1 - settle, nil) } // over the rest, so it never dims
        }
    }

    /// How hard the breeze blows at `t`, as the menu bar eases its own: up from `on`, and down from `off`.
    static func blow(_ t: Double, on: Double, off: Double?) -> Double {
        let up = Tween(0, 1, at: on, over: 0.5, Ease.inOutCubic)
        guard let off else { return up.value(t) }
        return Tween(up.value(off), 0, at: off, over: 0.6, Ease.inOutCubic).value(t)
    }

    /// What burnt, as dots along the coil it was, from the flame out to where the fuse ended when the session began,
    /// and a Boom flings them out.
    static func ash(_ ctx: CGContext, _ play: Replay, _ scene: FuseScene, _ t: Double, ink: CGColor, blow: Double) {
        let front = scene.head.value(t) + scene.length(t) // the flame, along the fuse
        let fling = play.bang.map { Ease.outCubic(min(1, max(0, (t - $0) / 0.8))) } ?? 0
        for (i, s) in play.ash.enumerated() where s > front + 0.001 {
            var p = scene.point(s, t)
            var alpha = 0.34 * min(1, (s - front) / 0.03)
            alpha *= min(1, max(0, (room + 9 - (p.x - FuseScene.start)) / 6)) // trailing off past the coil's room
            alpha *= 0.65 + 0.35 * cos(6 * .pi * s / FuseScene.full) // fainter where it turns back over the top, so it reads as a coil
            if fling > 0 {
                // Blown out from the mark, along the pill, what was in the blast itself gone, and stirred by a breeze,
                // as the fuse's own breeze stirs the rest.
                let a = atan2(p.y - ground.y, p.x - ground.x) + 0.8 * (noise(i, 1, 40) - 0.5), out = (3 + 13 * noise(i, 2, 40)) * fling
                alpha *= 1 - fling * max(0, 1 - hypot((p.x - ground.x) / 1.5, p.y - ground.y) / 6)
                p = CGPoint(x: p.x + out * cos(a) + 0.3 * blow * sin(t * 2.3 + s * 4),
                            y: ground.y + (p.y - ground.y) * (1 - 0.5 * fling) + 0.45 * out * sin(a) + 0.6 * blow * sin(2 * .pi * 1.4 * s - t * 5.5))
            }
            dot(ctx, p, 0.6, ink.copy(alpha: ink.alpha * alpha)!)
        }
    }

    /// A Boom's mark, `since` seconds after the bang: the ground singed, a scorch splashed out along the pill in two
    /// layers, a soft wide one under a ragged black heart, mottled, with streaks thrown out from under it, a spray of soot,
    /// and embers that cool from white to a dull red and glow up again in a breeze. The same session always leaves the
    /// same mark.
    static func blast(_ ctx: CGContext, since: Double, seed: Int, ink: CGColor, blow: Double, t: Double) {
        let c = ground, rand = { (i: Int, k: Int) in noise(seed, i, k) }
        let grow = Ease.outCubic(min(1, since / 0.45)), space = CGColorSpace(name: CGColorSpace.sRGB)!
        let black = { (a: Double) in CGColor(gray: 0, alpha: a) }, brown = { (a: Double) in Palette.soot.copy(alpha: a)! }
        let gradient = { (colours: [CGColor], at: [CGFloat]) in CGGradient(colorsSpace: space, colors: colours as CFArray, locations: at)! }
        // Wider than tall, as a pill would let it spread.
        let along = { (a: Double, d: Double) in CGPoint(x: c.x + 1.5 * d * cos(a), y: c.y + 0.75 * d * sin(a)) }
        let spread = { (draw: () -> Void) in
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: 1.5 * grow, y: 0.75 * grow)
            draw()
            ctx.restoreGState()
        }
        ctx.saveGState()
        spread { // the ground around it, singed
            ctx.drawRadialGradient(gradient([brown(0.4), brown(0.16), brown(0)], [0, 0.5, 1]), startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 16, options: [])
        }
        // Streaks thrown out from under it, tapering away.
        for i in 0..<9 {
            let a = 2 * .pi * (Double(i) + 0.8 * rand(i, 1)) / 9, reach = (8 + 13 * pow(rand(i, 2), 0.8)) * grow
            let w = 0.25 + 0.45 * rand(i, 3), d = CGPoint(x: 1.5 * cos(a), y: 0.75 * sin(a))
            let n = hypot(d.x, d.y), u = CGPoint(x: d.x / n, y: d.y / n), far = reach * n / 1.5 // shorter up and down
            let base = CGPoint(x: c.x + 3 * u.x, y: c.y + 3 * u.y), end = CGPoint(x: c.x + far * u.x, y: c.y + far * u.y)
            ctx.saveGState()
            ctx.beginPath()
            ctx.move(to: CGPoint(x: base.x - w * u.y, y: base.y + w * u.x))
            ctx.addLine(to: end)
            ctx.addLine(to: CGPoint(x: base.x + w * u.y, y: base.y - w * u.x))
            ctx.closePath()
            ctx.clip()
            ctx.drawLinearGradient(gradient([black(0.55), black(0.22), black(0)], [0, 0.5, 1]), start: base, end: end, options: [])
            ctx.restoreGState()
        }
        // The scorch: a ragged ring of spikes of every length and width, filled dark to the middle.
        let splash = { (layer: Int, count: Int, width: Double, reach: Double, colours: [CGColor], radius: Double) in
            spread {
                let spikes = (0..<count).map { k in
                    (a: 2 * .pi * (Double(k) + 0.9 * rand(k, 4 + 10 * layer)) / Double(count), len: reach * pow(rand(k, 5 + 10 * layer), 1.5),
                     w: width * (0.5 + rand(k, 6 + 10 * layer)))
                }
                ctx.beginPath()
                for j in 0...240 {
                    let a = 2 * .pi * Double(j) / 240
                    var r = 4.5 + 0.5 * sin(5 * a + rand(layer, 7) * 6) + 0.35 * sin(13 * a + rand(layer, 8) * 6)
                    for s in spikes { let x = max(0, 1 - abs(remainder(a - s.a, 2 * .pi)) / s.w); r += s.len * x * x }
                    if j == 0 { ctx.move(to: CGPoint(x: r * cos(a), y: r * sin(a))) } else { ctx.addLine(to: CGPoint(x: r * cos(a), y: r * sin(a))) }
                }
                ctx.closePath()
                ctx.clip()
                ctx.drawRadialGradient(gradient(colours, [0, 0.3, 0.65, 1]), startCenter: .zero, startRadius: 0, endCenter: .zero,
                                       endRadius: radius, options: [])
            }
        }
        splash(0, 12, 0.5, 9, [black(0.38), black(0.28), brown(0.14), brown(0)], 15) // soft and wide
        splash(1, 19, 0.2, 5.5, [black(0.9), black(0.8), black(0.4), black(0)], 10) // the black heart
        // Mottled, so it reads as soot, not paint.
        for i in 0..<14 {
            let p = along(2 * .pi * rand(i, 40), (0.5 + 6 * rand(i, 41)) * grow), r = 1.2 + 2.3 * rand(i, 42)
            let dark = rand(i, 43) < 0.6
            ctx.drawRadialGradient(gradient([dark ? black(0.3) : brown(0.35), brown(0), brown(0), brown(0)], [0, 1, 1, 1]),
                                   startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
        }
        // A spray of soot, thickest at the scorch's edge, flying out with the blast.
        for i in 0..<130 {
            let fly = Ease.outCubic(min(1, since / (0.3 + 0.6 * rand(i, 10)))), d = (3.5 + 15 * pow(rand(i, 11), 1.3)) * fly
            let r = 0.12 + 0.34 * rand(i, 12) * rand(i, 12)
            dot(ctx, along(2 * .pi * rand(i, 13), d), r, black((0.85 - 0.035 * d) * (0.35 + 0.65 * rand(i, 14))))
        }
        // Embers in the scorch: white-hot, cooling to a dull red, and fanned back up by a breeze.
        for i in 0..<4 {
            let p = along(2 * .pi * rand(i, 30), 1 + 5 * rand(i, 31))
            let fan = blow * (0.55 + 0.45 * sin(t * (7 + 6 * rand(i, 32)) + 6 * rand(i, 33)))
            let heat = min(1, max(0, 1 - since / (0.8 + 0.8 * rand(i, 34))) + 0.75 * fan)
            let colour = heat > 0.5 ? Palette.mix(Palette.orange, Palette.yellow, 2 * heat - 1)
                : Palette.mix(Palette.mix(Palette.red, Palette.soot, 0.45), Palette.orange, 2 * heat)
            glow(ctx, p, radius: 1.2 + 1.8 * heat, Palette.orange, alpha: 0.12 + 0.5 * heat)
            dot(ctx, p, 0.32 + 0.16 * rand(i, 35), colour)
        }
        ctx.restoreGState()
    }
}

/// The session as the menu bar showed it, every swing of 15 % or more, in the order they happened, each given as long
/// as the fuse takes to make it: fed in, burnt down, fed back. A smaller swing is a scratch, and isn't shown. A Boom
/// swings the same way to where it caught, then the race, the silence and the bang.
// Why: the words and the bars use the same thresholds (docs/why.md#session-story)
struct Replay {
    let start: Double
    var steps: [(at: Double, look: FuseLook)] = []
    var spans: [(at: Double, from: Int, to: Int)] = [] // when each step starts, and the stretch of the line it plays
    var ash: [Double] = [] // where along the fuse a dot of ash goes
    var bang: Double?
    var end = 0.0

    // ponytail: every pill's replay by its line, cleared past 64; a list only ever shows a few dozen
    nonisolated(unsafe) private static var made: [[Double]: Replay] = [:] // drawn on the main thread only

    /// The replay for a line, made once: it's drawn every frame a pill moves, and asked for on every move of a pointer.
    static func of(_ levels: [Double], boomed: Bool) -> Replay {
        let key = levels + [boomed ? 1 : 0]
        if let made = made[key] { return made }
        if made.count > 64 { made.removeAll() }
        let new = Replay(levels, boomed: boomed)
        made[key] = new
        return new
    }

    init(_ levels: [Double], boomed: Bool) {
        start = levels.first ?? 1
        let blew = levels.firstIndex { $0 < 0.001 } ?? levels.count - 1
        let moves = Self.turns(boomed ? Array(levels.dropLast()) : levels).dropFirst() + (boomed ? [blew] : [])
        var t = 0.15, now = start, head = 0.0, from = 0 // where the fuse starts, along it: what's fed in runs it back
        for i in moves where abs((boomed && i == blew ? 0 : levels[i]) - now) > 0.01 {
            let l = boomed && i == blew ? 0 : levels[i]
            spans.append((t, from, i))
            from = i
            if boomed, l < 0.001 {
                steps.append((t, FuseLook(phase: .fusing, left: 0)))
                lay(head: head, to: head)
                t += FuseScene.raceFor + 0.5
                steps.append((t, FuseLook(phase: .blown, left: 0)))
                bang = t
                end = t + 1.3
                return
            }
            steps.append((t, FuseLook(left: l)))
            if l > now {
                head -= l - now
                t += 1 + 0.8 * (l - now) // the feed, and a beat
            } else {
                // The burn: quick, then a crawl through the last third, as `FuseScene.burn` times it.
                let fast = max(0, now - max(l, 1.0 / 3)), crawl = max(0, min(now, 1.0 / 3) - l)
                t += 0.25 + max(0.3, (fast > 0 ? 0.45 + 0.75 * fast : 0) + (crawl > 0 ? 1.2 + 9 * crawl : 0))
            }
            now = l
        }
        lay(head: head, to: head + now)
        end = t + 0.3
    }

    /// A dot of ash every so often along the coil, as it rests at the end, from where the fuse first ended back to the
    /// lowest the flame got: evenly along it, so a tight turn has no more than a loose one.
    private mutating func lay(head: Double, to low: Double) {
        var last: CGPoint?, run = 2.4
        for s in stride(from: start, through: low, by: -0.002) {
            let p = FuseScene.restingPoint(s, head: head, tail: start, room: SessionFuse.room)
            if let q = last { run += hypot(p.x - q.x, p.y - q.y) }
            last = p
            if run >= 2.4 { ash.append(s); run = 0 }
        }
    }

    /// The line's turning points, from its start to its end, leaving out every swing smaller than 15 %.
    static func swings(_ line: [Double]) -> [Double] { turns(line).map { line[$0] } }

    /// Where along the line its turning points are.
    static func turns(_ line: [Double]) -> [Int] {
        guard let first = line.first else { return [] }
        var points = [0], turn = 0, way = 0.0 // the furthest it's gone since the last turning point, and which way
        for (i, l) in line.enumerated().dropFirst() {
            if way == 0 { if abs(l - first) >= 0.15 { (turn, way) = (i, l > first ? 1 : -1) }; continue }
            if (l - line[turn]) * way > 0 { turn = i } else if abs(l - line[turn]) >= 0.15 { points.append(turn); (turn, way) = (i, -way) }
        }
        if way != 0 { points.append(turn) }
        if abs(line[line.count - 1] - line[points[points.count - 1]]) > 0.01 { points.append(line.count - 1) } // where it really ended
        return points
    }

    /// The fuse at `t`, with a breeze through it from `wind.on` till `wind.off`.
    func scene(at t: Double, wind: (on: Double, off: Double?)? = nil) -> FuseScene {
        var scene = FuseScene()
        scene.held = (start, SessionFuse.room)
        scene.update(FuseLook(left: start), at: -10, animated: false)
        for s in steps where s.at <= t { scene.update(s.look, at: s.at) }
        if let wind, bang == nil, wind.on <= t {
            scene.update(FuseLook(left: scene.look.left, rating: true), at: wind.on)
            if let off = wind.off, off <= t { scene.update(FuseLook(left: scene.look.left), at: off) }
        }
        return scene
    }
}
