import AppKit
import SwiftUI

/// What the menu bar fuse shows: facts from the game, nothing else. `FuseScene` decides how each change looks.
public struct FuseLook: Equatable {
    public enum Phase: Equatable { case offline, lit, fusing, blown }
    public var phase = Phase.lit
    /// The share of the stick that's left, 0...1, while lit.
    public var left = 1.0
    /// The latest prompt, whether the model is still rating it, and the share of the stick its heat burnt. One prompt
    /// can burn the tip and feed new fuse in at the start at once, when it's cool too; `left` only has the difference.
    public var prompt: Double?
    public var rating = false
    public var bite = 0.0
    /// Fusing: when it bangs.
    public var bangAt: Date?
    /// Blown: the tier's name and number (1 Boom, 2 Chain reaction, 3 Meltdown), the heat climbing toward the next
    /// tier, 0...1, and whether it has quieted down, 10 minutes after the Boom or its last new tier.
    public var name = "Boom"
    public var tier = 1
    public var heat = 0.0
    public var quiet = false

    public init(phase: Phase = .lit, left: Double = 1, prompt: Double? = nil, rating: Bool = false, bite: Double = 0,
                bangAt: Date? = nil, name: String = "Boom", tier: Int = 1, heat: Double = 0, quiet: Bool = false) {
        self.phase = phase; self.left = left; self.prompt = prompt; self.rating = rating; self.bite = bite
        self.bangAt = bangAt; self.name = name; self.tier = tier; self.heat = heat; self.quiet = quiet
    }
}

/// The menu bar fuse, drawn as a pure function of time, so a preview can stop it on any frame. Only the fuse: a coil
/// fixed at its start on the left, a little imperfect, like a spring. The more fuse, the tighter its coils; the less,
/// the wider they spread. It moves when a prompt does something, and is still in between.
/// - While the model rates a prompt, the tip smoulders. If it was nothing, the ember just fades.
/// - Heat lights the tip and burns it away, right to left: the flame flares and runs, sparks fly, the coils spring
///   apart, and what burnt chars and falls as ash. The flame burns on for a few seconds, longer the less is left, then
///   goes out in a puff.
/// - Cool feeds new fuse in at the start, left to right, green and twinkling, squeezing the coils together. One prompt
///   can do both.
/// - Burnt through, it fizzes where it started, harder as the bang nears, and its last moments slow almost to a stop.
/// - The bang is the one show: a flash, a shockwave, sparks and a red BOOM. It burns out into smoke, a beat of nothing,
///   and then it's calm: a symbol and a word in the menu bar's own colour. The tier's name, "Still burning" while the
///   heat keeps coming, "Cooled off" once it's quiet, swapped with a little spring and nothing more.
/// - A new session feeds in a fresh fuse.
///
/// Coordinates are points, y up, measured from the right edge (x ≤ 0), since a menu bar item grows to the left.
public struct FuseScene {
    public static let fuseWidth = 36.0
    /// How long the fuse's last moments stretch out before the bang.
    // Why: anticipation, and a beat of stillness before the hit (hq: docs/research/game-feel-and-motivation.md)
    public static let slowMo = 1.4
    /// The bang's show: loud, then burning out, then a beat of nothing before the calm word.
    static let loudFor = 2.4, outFor = 0.45, emptyFor = 1.0
    static var calmAfter: Double { loudFor + outFor + emptyFor }
    /// How long the calm tier's name stays after the bang or a new tier, before the heat or the quiet takes over.
    static let nameFor = 5.0
    /// How long the flame burns on after a burn: with plenty left, past half, in the last third.
    static let flameFor = [2.5, 3.5, 5.0]
    private(set) var look = FuseLook()
    /// No motion: Reduce Motion, or a still preview.
    var still = false

    // The fuse is material from `head` (its start, where cool feeds it in) to `tail` (its burning tip).
    private var head = Tween(0)
    private var tail = Tween(1)
    private var boom = Tween(0)    // the calm symbol's size, 0...1
    private var named = Tween(0)   // the calm word, 0...1
    private var hush = Tween(0)    // 1 once the Boom has quieted down
    private var landing = Tween(1) // the loud burst flying from the ember to its place, 0...1
    private var bangFrom = 0.0
    private var bangT = -1e9       // when it banged, for the show
    private var loudName = ""
    private var captions: [(at: Double, caption: Caption)] = [] // what the calm Boom says, and from when
    private var nameUntil = 0.0
    private var wide = fuseWidth   // the width to keep until `shrinkAt`, so nothing is cut off mid-move
    private var shrinkAt = 0.0
    private var litUntil = 0.0     // when the flame goes out
    private var bangAt = 0.0
    private var fizzFrom = 0.0
    private var effects: [Effect] = []
    private var seed = 1

    /// Moves to `new`. Without `animated` it snaps, as on launch.
    mutating func update(_ new: FuseLook, at t: Double, animated: Bool = true) {
        let old = look, before = width(at: t)
        look = new
        if let date = new.bangAt { bangAt = t + date.timeIntervalSinceNow }
        // Wider at once, narrower only after the move, and never while blown, so the menu bar doesn't jitter.
        defer { wide = max(before, Self.width(new)); shrinkAt = new.phase == .blown ? .infinity : t + 1.9 }
        guard animated, !still else { return snap(t) }
        switch (old.phase, new.phase) {
        case (.lit, .lit), (.offline, .lit), (.lit, .offline):
            let delta = new.left - old.left
            var bite = max(0, -delta), mend = max(0, delta)
            if new.prompt != nil, new.prompt != old.prompt || (old.rating && !new.rating) { // a prompt's verdict is in
                bite = max(-delta, new.prompt == old.prompt ? max(0, new.bite - old.bite) : new.bite)
                mend = delta + bite // its cool fed fuse in while its heat burnt the tip
            }
            if bite > 0.001 { burn(bite, t) }
            if mend > 0.001 { grow(mend, t, held: old.left <= 1.0 / 3 && new.left > 1.0 / 3) }
            if old.rating && !new.rating && bite <= 0.001 { effects.append(.ember(t, cool: mend > 0.001)) } // the smoulder goes out
        case (.lit, .fusing), (.offline, .fusing):
            fizzFrom = t + burn(tail.to - head.to, t)
        case (.fusing, .blown), (.lit, .blown), (.offline, .blown):
            bang(t)
        case (.blown, .blown):
            // Escalating and calming down are quiet: the word and the symbol swap, and that's all.
            let calm = max(t, bangT + Self.calmAfter)
            if new.tier > old.tier {
                nameUntil = calm + Self.nameFor
                say(Self.named(new), at: calm)
                effects.append(.pop(calm, 0.35))
            }
            say(Self.caption(new), at: max(calm, nameUntil))
            if new.quiet != old.quiet { hush = Tween(hush.value(t), new.quiet ? 1 : 0, at: t, over: 0.8) }
        case (.blown, .lit), (.blown, .offline), (.fusing, .lit), (.fusing, .offline):
            fresh(t, to: new.phase == .lit ? new.left : 1)
        default:
            snap(t)
        }
    }

    /// Something's happening: draw every frame.
    func busy(at t: Double) -> Bool {
        guard !still else { return false }
        return [head, tail, boom, named, hush, landing].contains { !$0.done(t) } || effects.contains { t < $0.end }
            || t < bangT + Self.calmAfter + 0.6 // the show
            || (captions.last.map { t < $0.at + 0.6 } ?? false) // a swap to come, or under way
            || (shrinkAt.isFinite && t < shrinkAt && wide > Self.width(look)) // still has to narrow
    }

    /// Something's alive: the flame, the smoulder, the fizz. A low frame rate is plenty.
    func idling(at t: Double) -> Bool {
        guard !still else { return false }
        return burning(at: t) || look.phase == .fusing || (look.phase == .lit && look.rating)
    }

    /// How wide the item is at `t`: it widens at once and narrows only once the move is over.
    func width(at t: Double) -> Double {
        t < shrinkAt ? max(wide, Self.width(look)) : Self.width(look)
    }

    static func width(_ look: FuseLook) -> Double {
        guard look.phase == .blown else { return fuseWidth }
        return max(loudWidth(look.name.uppercased()), named(look).width, caption(look).width)
    }

    func length(_ t: Double) -> Double { max(0, tail.value(t) - head.value(t)) }

    private func burning(at t: Double) -> Bool { look.phase == .lit && length(t) > 0.002 && t < litUntil }

    // MARK: Events

    private mutating func snap(_ t: Double) {
        let blown = look.phase == .blown
        head = Tween(0)
        tail = Tween(look.phase == .lit || look.phase == .offline ? look.left : 0)
        boom = Tween(blown ? 1 : 0)
        named = Tween(blown ? 1 : 0)
        hush = Tween(look.quiet ? 1 : 0)
        landing = Tween(1)
        bangT = -1e9
        captions = blown ? [(t - 1, Self.caption(look))] : []
        nameUntil = 0
        effects = []
        litUntil = 0
        fizzFrom = t
    }

    /// Burns `bite` off the tip. Returns how long it takes: a bigger bite burns longer.
    @discardableResult
    private mutating func burn(_ bite: Double, _ t: Double) -> Double {
        let over = 0.45 + 0.75 * bite, from = tail.value(t), to = tail.to - bite
        tail = Tween(from, to, at: t, over: over, Ease.outCubic)
        seed += 1
        effects.append(.char(t, from: from, to: to, over: over, seed: seed))
        effects.append(.sparks(t, point(from, t), n: 7, seed: seed, speed: 40, spread: 2.8, palette: .fire))
        effects.append(.flare(t))
        effects.append(.wiggle(t, 0.8, 34))
        effects.append(.spring(t, 0.1)) // what's left springs apart
        // It burns on a while, then goes out in a puff.
        let danger = look.left <= 1.0 / 3 ? 2 : look.left <= 0.5 ? 1 : 0
        douse(at: max(litUntil, t + over + Self.flameFor[danger]), t)
        return over
    }

    /// Feeds `mend` of new fuse in at the start.
    private mutating func grow(_ mend: Double, _ t: Double, held: Bool) {
        let over = 0.8 + 0.8 * mend, from = head.value(t), to = head.to - mend
        head = Tween(from, to, at: t, over: over, Ease.inOutCubic)
        seed += 1
        effects.append(.cool(t, from: from, to: to, over: over, seed: seed))
        effects.append(.spring(t + over * 0.5, -0.08)) // squeezed together
        // Climbing out of the last third: a close call, held together.
        if held {
            let at = t + over * 0.6, tip = Self.restingPoint(tail.to, head: to, tail: tail.to)
            effects.append(.sparks(at, tip, n: 9, seed: seed, speed: 16, spread: 2 * .pi, palette: .cool))
            effects.append(.held(at, tip))
            effects.append(.wiggle(at, 0.7, 20))
        }
        if look.left >= 0.999, litUntil > t + over { douse(at: t + over, t) } // grown back whole: the flame goes out
    }

    /// The flame goes out at `at`, in a puff, unless something lights it again first.
    private mutating func douse(at: Double, _ t: Double) {
        effects.removeAll { if case .douse(let d) = $0 { return d > t } else { return false } }
        litUntil = at
        effects.append(.douse(at))
    }

    /// The one big moment: a flash, a shockwave and a spray of sparks out of the ember, and the loud BOOM thrown out of
    /// it. Then it burns out into smoke, and after a beat of nothing the calm word comes in.
    private mutating func bang(_ t: Double) {
        let from = point(head.value(t), t)
        head = Tween(head.value(t))
        tail = Tween(head.value(t))
        bangT = t
        bangFrom = from.x
        loudName = look.name.uppercased()
        landing = Tween(0, 1, at: t, over: 0.55, Ease.outBack)
        let calm = t + Self.calmAfter
        boom = Tween(0, 1, at: calm, over: 0.55, Ease.outBack)
        named = Tween(0, 1, at: calm + 0.1, over: 0.45, Ease.outCubic)
        hush = Tween(look.quiet ? 1 : 0)
        nameUntil = calm + Self.nameFor
        captions = [(calm, Self.named(look))]
        say(Self.caption(look), at: nameUntil)
        litUntil = 0
        seed += 1
        effects.append(.flash(t, from))
        effects.append(.ring(t, from))
        effects.append(.shake(t, 1.8))
        effects.append(.sparks(t, from, n: 40, seed: seed, speed: 72, spread: 2 * .pi, palette: .fire))
        let spot = Self.loudSpot(loudName), out = t + Self.loudFor
        effects.append(.puff(out, CGPoint(x: spot, y: 9)))
        effects.append(.puff(out + 0.1, CGPoint(x: (spot - 2) / 2, y: 8)))
        effects.append(.puff(out + 0.2, CGPoint(x: -6, y: 9)))
    }

    /// A new session: the Boom goes, and a fresh fuse feeds in from the start.
    private mutating func fresh(_ t: Double, to left: Double) {
        boom = Tween(boom.value(t), 0, at: t, over: 0.3, Ease.inCubic)
        named = Tween(named.value(t), 0, at: t, over: 0.2)
        bangT = -1e9
        head = Tween(0, -left, at: t + 0.35, over: 0.6 + 0.9 * left, Ease.outCubic)
        tail = Tween(0)
        hush = Tween(0)
        effects = [.spring(t + 0.9 + 0.6 * left, -0.12)] // boing
        litUntil = 0
    }

    /// From `at`, the Boom says `caption`, if it isn't already about to.
    private mutating func say(_ caption: Caption, at t: Double) {
        captions.removeAll { $0.at > t } // a later plan gives way
        guard captions.last?.caption != caption else { return }
        captions.append((t, caption))
        if captions.count > 3 { captions.removeFirst(captions.count - 3) }
    }

    // MARK: Drawing

    static let ink = CGColor(gray: 0, alpha: 0.85)

    /// Draws the frame at `t` with the item's right edge at the context's origin, y up from the bottom of an 18-point
    /// band. `ink` is the menu bar's text colour.
    func draw(_ ctx: CGContext, at t: Double, ink: CGColor = ink) {
        ctx.saveGState()
        if look.phase == .offline { ctx.setAlpha(0.4) }
        let from = head.value(t), to = tail.value(t)
        if to - from > 0.002 { stroke(ctx, from, to, t, ink, width: 1.5) }
        for e in effects { drawUnder(e, ctx, t, ink: ink) }
        if look.phase == .fusing && t >= fizzFrom { drawFizz(ctx, t) }
        if burning(at: t) { drawFlame(ctx, t) } else if look.phase == .lit && look.rating && to - from > 0.002 { drawSmoulder(ctx, t) }
        if t < bangT + Self.loudFor + Self.outFor { drawLoud(ctx, t) }
        if boom.value(t) > 0.01 { drawBoom(ctx, t, ink: ink) }
        for e in effects { drawOver(e, ctx, t, ink: ink) }
        ctx.restoreGState()
    }

    /// The lit tip: a flame that flickers and sways, amber with plenty left, orange past half, red and nervous in the last
    /// third, and spits the odd spark. A burn makes it flare; going out, it shrinks into its puff.
    private func drawFlame(_ ctx: CGContext, _ t: Double) {
        let at = point(tail.value(t), t)
        let danger = look.left <= 1.0 / 3 ? 2 : look.left <= 0.5 ? 1 : 0
        let flare = effects.reduce(0.0) { acc, e in
            if case .flare(let t0) = e, t >= t0 { return acc + exp(-4 * (t - t0)) } else { return acc }
        }
        let dying = min(1, max(0, (litUntil - t) / 0.5))
        flame(ctx, at, size: [2.7, 3.3, 4.0][danger] * (1 + 0.7 * flare) * (0.3 + 0.7 * dying), t, outer: [Palette.amber, Palette.orange, Palette.red][danger])
        guard !still else { return }
        let rate = ([1.2, 2.5, 5.0][danger] + 30 * flare) * dying
        emit(ctx, from: t - 0.6, to: t, every: 1 / 30.0, rate: { _ in rate }, seed: 11, t: t) { born in
            (self.point(self.tail.value(born), born), 18, 1.6)
        }
    }

    /// The model is rating the latest prompt: the tip smoulders, a small ember breathing.
    private func drawSmoulder(_ ctx: CGContext, _ t: Double) {
        let at = point(tail.value(t), t), breath = still ? 0.5 : 0.5 + 0.5 * sin(t * 5)
        glow(ctx, at, radius: 2.6 + breath, Palette.amber, alpha: 0.25 + 0.2 * breath)
        dot(ctx, at, 0.8 + 0.25 * breath, Palette.mix(Palette.orange, Palette.yellow, breath))
    }

    /// Burnt through: the flame sits where the fuse began and fizzes, swelling as the bang nears, while its last moments
    /// slow almost to a stop, sparks hanging in the air.
    private func drawFizz(_ ctx: CGContext, _ t: Double) {
        let at = point(head.value(t), t), slow = fuseClock(t)
        let urgency = still ? 0 : min(1, max(0, 1 - (bangAt - t) / Self.slowMo))
        glow(ctx, at, radius: 4 + 5 * urgency, Palette.red, alpha: 0.4 + 0.35 * urgency)
        flame(ctx, at, size: 4 + 2.4 * urgency, slow, outer: Palette.red)
        guard !still else { return }
        emit(ctx, from: max(fizzFrom, slow - 0.7), to: slow, every: 1 / 90.0, rate: { _ in 40 + 50 * urgency }, seed: 7, t: slow) { _ in
            (at, 30, 2.6)
        }
    }

    /// The fizz's own time: normal, then in the last `slowMo` seconds it slows to a twelfth.
    private func fuseClock(_ t: Double) -> Double {
        let begin = bangAt - Self.slowMo
        guard !still, t > begin else { return t }
        let u = min(1, (t - begin) / Self.slowMo) // the speed eases from 1 down to 0.08: the integral of that
        return begin + Self.slowMo * (u - 0.92 * (u * u * u - u * u * u * u / 2))
    }

    /// A teardrop flame on `base`, `size` tall, with a yellow heart and a white-hot root.
    private func flame(_ ctx: CGContext, _ base: CGPoint, size: Double, _ t: Double, outer: CGColor) {
        let flick = still ? 0 : 0.16 * sin(t * 23) + 0.1 * sin(t * 37 + 1.3) + 0.07 * sin(t * 61)
        let sway = still ? 0 : 0.45 * sin(t * 9) + 0.25 * sin(t * 15 + 2)
        let h = size * (1 + flick), w = size * 0.36
        glow(ctx, CGPoint(x: base.x, y: base.y + h * 0.3), radius: h * 1.3, outer, alpha: 0.32)
        func drop(_ w: Double, _ h: Double, _ sway: Double, _ colour: CGColor) {
            let top = CGPoint(x: base.x + sway, y: base.y + h)
            ctx.beginPath()
            ctx.move(to: top)
            ctx.addQuadCurve(to: CGPoint(x: base.x - w, y: base.y), control: CGPoint(x: base.x - w * 1.05 + sway * 0.3, y: base.y + h * 0.5))
            ctx.addArc(center: base, radius: w, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
            ctx.addQuadCurve(to: top, control: CGPoint(x: base.x + w * 1.05 + sway * 0.3, y: base.y + h * 0.5))
            ctx.setFillColor(colour)
            ctx.fillPath()
        }
        drop(w, h, sway, outer)
        drop(w * 0.62, h * 0.6, sway * 0.6, Palette.yellow)
        dot(ctx, base, w * 0.38, Palette.white)
    }

    // MARK: The bang

    /// The show right after the bang: a burst in colour and a red BOOM, glowing and breathing, until it burns out.
    private func drawLoud(_ ctx: CGContext, _ t: Double) {
        let age = t - bangT, out = min(1, max(0, (age - Self.loudFor) / Self.outFor))
        var shake = 0.0
        for e in effects { if case .shake(let t0, let s) = e, t >= t0 { let x = t - t0; shake += s * exp(-9 * x) * sin(70 * x) } }
        let spot = Self.loudSpot(loudName), fade = 1 - out
        let at = CGPoint(x: bangFrom + (spot - bangFrom) * landing.value(t) + shake, y: 9)
        let breathe = still ? 1 : 1 + 0.06 * sin(age * 7)
        let r = 5.6 * Ease.outBack(min(1, age / 0.5)) * breathe * (1 - 0.6 * out)
        ctx.saveGState()
        ctx.setAlpha(fade)
        glow(ctx, at, radius: r * 1.9, Palette.red, alpha: 0.45)
        Self.burst(ctx, at, r, Palette.orange, core: Palette.yellow)
        let word = Ease.outBack(min(1, max(0, (age - 0.12) / 0.45)))
        if word > 0.05 {
            let line = Self.line(loudName, font: Self.loudFont), w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.saveGState()
            ctx.translateBy(x: -2 + shake * 0.5, y: 9)
            ctx.scaleBy(x: word * (1 - 0.3 * out), y: word * (1 - 0.3 * out))
            glow(ctx, CGPoint(x: -w / 2, y: 0), radius: w * 0.7, Palette.red, alpha: 0.25)
            ctx.setFillColor(Palette.red)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: -w, y: -Self.loudFont.capHeight / 2)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    static func loudSpot(_ name: String) -> Double { -(loudWidth(name) - 9) }
    static func loudWidth(_ name: String) -> Double {
        CTLineGetTypographicBounds(line(name, font: loudFont), nil, nil, nil).rounded(.up) + 18
    }

    private static let loudFont: NSFont = {
        let plain = NSFont.systemFont(ofSize: 10, weight: .heavy)
        return plain.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 10) } ?? plain
    }()

    /// Eight rays, long and short, around a dot.
    static func burst(_ ctx: CGContext, _ c: CGPoint, _ r: Double, _ colour: CGColor, core: CGColor) {
        ctx.beginPath()
        for i in 0..<8 {
            let a = 0.2 + Double(i) * .pi / 4, reach = i % 2 == 0 ? 1 : 0.68
            ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.42, y: c.y + sin(a) * r * 0.42))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r * reach, y: c.y + sin(a) * r * reach))
        }
        ctx.setStrokeColor(colour)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.strokePath()
        dot(ctx, c, max(0.8, r * 0.2), core)
    }

    // MARK: The calm Boom

    /// What the Boom says: an SF Symbol and a word.
    struct Caption: Equatable {
        var symbol: String
        var text: String
        /// The symbol, a gap and the word, with the menu bar item's own margin.
        var width: Double { textWidth(text) + 24 }
        /// Where the symbol sits, before the word.
        var spot: Double { -(textWidth(text) + 12) }
    }

    static func named(_ look: FuseLook) -> Caption { Caption(symbol: "burst.fill", text: look.name) }

    /// After the name has had its moment: "Still burning" while heat keeps coming, "Cooled off" once it's quiet.
    static func caption(_ look: FuseLook) -> Caption {
        if look.heat >= 0.25 { return Caption(symbol: "flame.fill", text: "Still burning") }
        if look.quiet { return Caption(symbol: "wind", text: "Cooled off") }
        return named(look)
    }

    /// The Boom in the menu bar's colour: the symbol flies out of the ember and lands before the word. A new caption
    /// springs in from below as the old one rises away.
    private func drawBoom(_ ctx: CGContext, _ t: Double, ink: CGColor) {
        guard let now = captions.last(where: { $0.at <= t }) ?? captions.first else { return }
        let before = captions.last { $0.at < now.at }?.caption
        let k = still ? 1 : min(1, max(0, (t - now.at) / 0.45))
        var pop = 1.0, shake = 0.0
        for e in effects {
            if case .pop(let t0, let s) = e, t >= t0 { let x = t - t0; pop *= 1 + s * exp(-6 * x) * sin(17 * x) }
            if case .shake(let t0, let s) = e, t >= t0 { let x = t - t0; shake += s * exp(-9 * x) * sin(70 * x) }
        }
        let alpha = 1 - 0.3 * hush.value(t), size = boom.value(t) * pop, word = named.value(t)
        // Each symbol keeps to its own word; at the bang it flies there out of the ember.
        let flying = landing.value(t)
        let x = { (spot: Double) in bangFrom + (spot - bangFrom) * flying + shake }
        // One after the other: the old caption rises away in the first 40%, the new one springs up from below after it.
        let leaving = max(0, 1 - k / 0.4), arriving = before == nil ? 1 : max(0, (k - 0.3) / 0.7)
        if let before, leaving > 0 {
            Self.symbol(ctx, before.symbol, at: CGPoint(x: x(before.spot), y: 9 + 4 * (1 - leaving)), scale: size * (0.7 + 0.3 * leaving), ink: ink, alpha: alpha * leaving)
            Self.text(ctx, before.text, y: 4 * (1 - leaving), ink: ink, alpha: alpha * word * leaving)
        }
        let rise = before == nil ? 0 : -4 * (1 - Ease.outBack(arriving))
        Self.symbol(ctx, now.caption.symbol, at: CGPoint(x: x(now.caption.spot), y: 9 + rise), scale: size * (before == nil ? 1 : 0.6 + 0.4 * Ease.outBack(arriving)),
                    ink: ink, alpha: alpha * min(1, arriving))
        Self.text(ctx, now.caption.text, y: rise, ink: ink, alpha: alpha * word * min(1, arriving))
    }

    /// An SF Symbol in `ink`, centred on `at`.
    static func symbol(_ ctx: CGContext, _ name: String, at c: CGPoint, scale: Double, ink: CGColor, alpha: Double) {
        let colour = NSColor(cgColor: ink) ?? .labelColor
        guard scale > 0.05, alpha > 0.01, let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))) else { return }
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAlpha(alpha)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// A word in the menu bar's own font and `ink`, right-aligned at the edge, raised by `y`.
    static func text(_ ctx: CGContext, _ text: String, y: Double, ink: CGColor, alpha: Double) {
        guard alpha > 0.01, !text.isEmpty else { return }
        let line = Self.line(text), width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setFillColor(ink)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -2 - width, y: 9 - font.capHeight / 2 + y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static let font = NSFont.menuBarFont(ofSize: 0)

    private static func line(_ text: String, font: NSFont = font) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
    }

    static func textWidth(_ text: String) -> Double { CTLineGetTypographicBounds(line(text), nil, nil, nil).rounded(.up) }

    // MARK: Effects

    private enum Effect {
        case char(Double, from: Double, to: Double, over: Double, seed: Int) // the burnt-off tip: glowing, then ash
        case cool(Double, from: Double, to: Double, over: Double, seed: Int) // the fed-in start: green, twinkling
        case sparks(Double, CGPoint, n: Int, seed: Int, speed: Double, spread: Double, palette: Palette.Kind)
        case flare(Double)                  // the flame flares on a burn
        case wiggle(Double, Double, Double) // the coils flinch: amplitude, frequency
        case spring(Double, Double)         // the coils spring apart (+) or squeeze together (-)
        case shake(Double, Double)          // the Boom jolts
        case flash(Double, CGPoint)         // white heat at the bang
        case held(Double, CGPoint)          // a green glow: climbed out of the last third
        case ring(Double, CGPoint)          // a small shockwave
        case pop(Double, Double)
        case puff(Double, CGPoint)
        case douse(Double)               // the flame goes out, in a puff at the tip
        case ember(Double, cool: Bool)   // the smoulder fades: to nothing, or green

        var end: Double {
            switch self {
            case .char(let t, _, _, let over, _): t + over + 0.9
            case .cool(let t, _, _, let over, _): t + over + 1.1
            case .sparks(let t, _, _, _, _, _, _): t + 0.75
            case .flare(let t): t + 1
            case .wiggle(let t, _, _): t + 0.8
            case .spring(let t, _): t + 1.2
            case .shake(let t, _): t + 0.5
            case .flash(let t, _): t + 0.2
            case .held(let t, _): t + 0.6
            case .ring(let t, _): t + 0.4
            case .pop(let t, _): t + 0.9
            case .puff(let t, _): t + 1.4
            case .douse(let t): t + 1.4
            case .ember(let t, _): t + 0.6
            }
        }
    }

    private func drawUnder(_ e: Effect, _ ctx: CGContext, _ t: Double, ink: CGColor) {
        switch e {
        case .char(let t0, let from, let to, let over, let seed) where t >= t0:
            // Each bit of the burnt tip glows behind the flame, then dulls to ash and drops off.
            let front = tail.value(t)
            let steps = max(1, Int((from - front) * 90))
            for s in 0..<steps where front < from {
                let a = front + (from - front) * Double(s) / Double(steps), b = front + (from - front) * Double(s + 1) / Double(steps)
                let k = max(0, t - burnt(at: (a + b) / 2, t0, from, to, over)) / 0.45
                guard k < 1 else { continue }
                stroke(ctx, a, b, t, Palette.mix(Palette.orange, Palette.soot, k).copy(alpha: 1 - k * k)!, width: 1.6 - 0.4 * k)
            }
            guard !still else { return }
            for i in 0..<(3 + Int(16 * (from - to))) {
                let u = to + (from - to) * noise(seed, i, 5), born = burnt(at: u, t0, from, to, over) + 0.25, age = t - born
                guard age >= 0, age < 0.7 else { continue }
                let p = point(u, born)
                dot(ctx, CGPoint(x: p.x + 3 * (noise(seed, i, 6) - 0.5) * age, y: p.y - 22 * age * age), 0.55,
                    ink.copy(alpha: ink.alpha * 0.5 * (1 - age / 0.7))!)
            }
        case .cool(let t0, let from, let to, let over, let seed) where t >= t0:
            let front = max(head.value(t), to), fade = t < t0 + over ? 1 : max(0, 1 - (t - t0 - over) / 1.1)
            if front < from, fade > 0 { stroke(ctx, front, from, t, Palette.green.copy(alpha: fade)!, width: 1.7) }
            guard !still else { return }
            // Twinkles where it feeds in, drifting up.
            for i in 0..<(3 + Int(10 * (from - to))) {
                let u = to + (from - to) * noise(seed, i, 5)
                let born = t0 + over * Self.progress(of: u, from: from, to: to), age = t - born
                guard age >= 0, age < 0.9 else { continue }
                let p = point(u, born)
                twinkle(ctx, CGPoint(x: p.x, y: p.y + 2 + 6 * age), 1.6 * sin(.pi * age / 0.9), Palette.green)
            }
        default:
            break
        }
    }

    private func drawOver(_ e: Effect, _ ctx: CGContext, _ t: Double, ink: CGColor) {
        switch e {
        case .sparks(let t0, let at, let n, let seed, let speed, let spread, let palette) where t >= t0 && !still:
            for i in 0..<n { spark(ctx, from: at, born: t0, i: i, seed: seed, speed: speed, spread: spread, palette: palette, t: t) }
        case .flash(let t0, let at) where t >= t0 && t < t0 + 0.2:
            glow(ctx, at, radius: 9, Palette.white, alpha: 1 - (t - t0) / 0.2)
        case .held(let t0, let at) where t >= t0 && t < t0 + 0.6:
            let x = (t - t0) / 0.6
            glow(ctx, at, radius: 3 + 6 * x, Palette.green, alpha: 0.55 * (1 - x))
        case .ring(let t0, let at) where t >= t0 && t < t0 + 0.4:
            let x = (t - t0) / 0.4, r = 2 + 8 * (1 - pow(1 - x, 3))
            ctx.setStrokeColor(Palette.orange.copy(alpha: 0.9 * (1 - x))!)
            ctx.setLineWidth(1.4 - x)
            ctx.strokeEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
        case .puff(let t0, let at) where t >= t0 && t < t0 + 1.4 && !still:
            smoke(ctx, at, (t - t0) / 1.4, ink: ink, alpha: 0.32)
        case .douse(let t0) where t >= t0 && t < t0 + 1.4 && !still && look.phase == .lit:
            smoke(ctx, point(tail.value(t0), t0), (t - t0) / 1.4, ink: ink, alpha: 0.32)
        case .ember(let t0, let cool) where t >= t0 && t < t0 + 0.6 && look.phase == .lit:
            let k = (t - t0) / 0.6, at = point(tail.value(t), t), colour = cool ? Palette.green : Palette.amber
            glow(ctx, at, radius: 2.6 + 3 * k, colour, alpha: 0.4 * (1 - k))
            dot(ctx, at, 0.9 * (1 - k), colour)
        default:
            break
        }
    }

    /// When the burn's front passed `u`, for a burn from `from` to `to` that started at `t0`.
    private func burnt(at u: Double, _ t0: Double, _ from: Double, _ to: Double, _ over: Double) -> Double {
        let f = min(1, max(0, (from - u) / max(1e-9, from - to)))
        return t0 + over * (1 - pow(1 - f, 1.0 / 3)) // inverse of Ease.outCubic
    }

    /// Candidate sparks every `every` seconds from `from` to `to`, each kept by `rate` per second at its birth.
    /// `origin` gives a spark its start, speed and spread.
    private func emit(_ ctx: CGContext, from: Double, to: Double, every: Double, rate: (Double) -> Double, seed: Int, t: Double,
                      origin: (Double) -> (CGPoint, Double, Double)) {
        guard to >= from else { return }
        for k in Int((from / every).rounded(.down))...Int((to / every).rounded(.down)) {
            let born = Double(k) * every
            guard born >= from, noise(seed, k, 9) < rate(born) * every else { continue }
            let (at, speed, spread) = origin(born)
            spark(ctx, from: at, born: born, i: k, seed: seed, speed: speed, spread: spread, palette: .fire, t: t)
        }
    }

    /// One spark, born at `born`: flies out, mostly upward, falls, cools from white to red and fades. Cool ones are
    /// green twinkles that burst out and hang.
    private func spark(_ ctx: CGContext, from p: CGPoint, born: Double, i: Int, seed: Int, speed: Double, spread: Double,
                       palette: Palette.Kind, t: Double) {
        let life = 0.28 + 0.4 * noise(seed, i, 0), age = t - born
        guard age >= 0, age < life else { return }
        let a = .pi / 2 + spread * (noise(seed, i, 1) - 0.5), v = speed * (0.4 + 0.6 * noise(seed, i, 2))
        let k = age / life
        if palette == .cool {
            let out = 1 - pow(1 - k, 2)
            let at = CGPoint(x: p.x + cos(a) * v * out * life, y: p.y + sin(a) * v * out * life * 0.8)
            twinkle(ctx, at, 1.7 * sin(.pi * k), k < 0.15 ? Palette.white : Palette.green)
            return
        }
        let at = CGPoint(x: p.x + cos(a) * v * age, y: p.y + sin(a) * v * age - 45 * age * age)
        let colour = k < 0.12 ? Palette.white : k < 0.4 ? Palette.yellow : k < 0.7 ? Palette.orange : Palette.red
        dot(ctx, at, (0.35 + 0.4 * noise(seed, i, 3)) * (1 - 0.5 * k), colour.copy(alpha: 1 - k * k)!)
    }

    /// A four-pointed twinkle.
    private func twinkle(_ ctx: CGContext, _ c: CGPoint, _ r: Double, _ colour: CGColor) {
        guard r > 0.1 else { return }
        ctx.beginPath()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 + .pi / 2, reach = i % 2 == 0 ? r : r * 0.28
            let p = CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.closePath()
        ctx.setFillColor(colour)
        ctx.fillPath()
    }

    /// A little cloud of smoke, `k` of the way through its life: rises, spreads, fades.
    private func smoke(_ ctx: CGContext, _ at: CGPoint, _ k: Double, ink: CGColor, alpha: Double) {
        for (dx, dy, r) in [(-1.1, 0.0, 1.2), (0.9, 1.1, 1.0), (0.0, 2.4, 0.85)] {
            dot(ctx, CGPoint(x: at.x + dx * (1 + k) + 1.5 * k, y: at.y + 1 + dy + 5.5 * k), r * (1 + 1.4 * k),
                ink.copy(alpha: ink.alpha * alpha * (1 - k) * min(1, k * 8))!)
        }
    }

    // MARK: The coil

    public static let start = -33.0  // where the fuse is fixed, from the right edge
    static let pitch = 26.0   // how far a whole stick of fuse reaches, squeezed tight
    static let stretch = 0.9  // how much wider the coils spread as the fuse runs out
    static let radius = 3.0

    /// Where the bit of fuse at `s` sits when the fuse runs from `head` to `tail`, at rest. Three coils to a stick. Each
    /// coil keeps its own small quirks as it moves, since they belong to the fuse, not to the spot.
    static func restingPoint(_ s: Double, head: Double, tail: Double, spring: Double = 0) -> CGPoint {
        let reach = pitch * (1 + stretch * (1 - min(1, max(0, tail - head)))) * (1 + spring)
        let r = radius * (1 + 0.11 * quirk(s, 1)), angle = 6 * .pi * s + 0.22 * quirk(s, 2)
        return CGPoint(x: start + reach * (s - head) + r * sin(angle), y: 9.5 - r * cos(angle) + 0.4 * quirk(s, 3))
    }

    /// The same bit at `t`, as the coils spring and flinch: the start stays put, the tip moves most. In the last third
    /// the fuse trembles a little.
    private func point(_ s: Double, _ t: Double) -> CGPoint {
        let h = head.value(t), l = max(1e-6, tail.value(t) - h)
        var spring = 0.0
        if !still {
            for e in effects { if case .spring(let t0, let a) = e, t >= t0, t < t0 + 1.2 { let x = t - t0; spring += a * exp(-5 * x) * sin(13 * x) } }
        }
        var p = Self.restingPoint(s, head: h, tail: h + l, spring: spring)
        guard !still else { return p }
        let u = min(1.5, max(0, (s - h) / l))
        for e in effects {
            if case .wiggle(let t0, let amp, let freq) = e, t >= t0, t < t0 + 0.8 {
                let x = t - t0
                p.y += amp * u * exp(-6 * x) * sin(freq * x - 8 * u)
            }
        }
        if burning(at: t), look.left <= 1.0 / 3 { p.y += 0.22 * u * sin(t * 41 + s * 30) }
        return p
    }

    /// Smooth, uneven wobble along the fuse, -1...1.
    private static func quirk(_ s: Double, _ k: Double) -> Double {
        0.6 * sin(17.3 * s + 1.1 * k) + 0.4 * sin(29.7 * s + 2.3 * k * k)
    }

    private func stroke(_ ctx: CGContext, _ from: Double, _ to: Double, _ t: Double, _ colour: CGColor, width: Double) {
        let steps = max(2, Int((to - from) * 160))
        ctx.beginPath()
        ctx.move(to: point(from, t))
        for i in 1...steps { ctx.addLine(to: point(from + (to - from) * Double(i) / Double(steps), t)) }
        ctx.setStrokeColor(colour)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// When, as a share of an eased move from `from` to `to`, it reaches `u`.
    private static func progress(of u: Double, from: Double, to: Double) -> Double {
        let target = (u - from) / (to - from)
        var lo = 0.0, hi = 1.0
        for _ in 0..<20 { let m = (lo + hi) / 2; if Ease.inOutCubic(m) < target { lo = m } else { hi = m } }
        return lo
    }
}

// MARK: - Drawing helpers

private func dot(_ ctx: CGContext, _ at: CGPoint, _ r: Double, _ colour: CGColor) {
    ctx.setFillColor(colour)
    ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
}

private func glow(_ ctx: CGContext, _ at: CGPoint, radius: Double, _ colour: CGColor, alpha: Double) {
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [colour.copy(alpha: alpha)!, colour.copy(alpha: 0)!] as CFArray, locations: [0, 1]) else { return }
    ctx.drawRadialGradient(gradient, startCenter: at, startRadius: 0, endCenter: at, endRadius: radius, options: [])
}

/// The same random number for the same seed, index and channel, so every frame agrees on where a spark is.
private func noise(_ seed: Int, _ i: Int, _ channel: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: seed &* 73_856_093 ^ i &* 19_349_663 ^ channel &* 83_492_791)
    x ^= x >> 33; x &*= 0xff51_afd7_ed55_8ccd; x ^= x >> 33; x &*= 0xc4ce_b9fe_1a85_ec53; x ^= x >> 33
    return Double(x % 10_000) / 10_000
}

enum Palette {
    enum Kind { case fire, cool }
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    static let white = rgb(1, 0.97, 0.88)
    static let yellow = rgb(1, 0.84, 0.3)
    static let amber = rgb(1, 0.66, 0.16)
    static let orange = rgb(1, 0.45, 0.12)
    static let red = rgb(0.94, 0.2, 0.14)
    static let green = rgb(0.32, 0.85, 0.5)
    static let soot = rgb(0.32, 0.27, 0.24)

    static func mix(_ a: CGColor, _ b: CGColor, _ f: Double) -> CGColor {
        let x = a.components ?? [0, 0, 0, 1], y = b.components ?? [0, 0, 0, 1], f = min(1, max(0, f))
        return rgb(x[0] + (y[0] - x[0]) * f, x[1] + (y[1] - x[1]) * f, x[2] + (y[2] - x[2]) * f)
    }
}

// MARK: - Motion

enum Ease {
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inCubic(_ x: Double) -> Double { x * x * x }
    static func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func outBack(_ x: Double) -> Double { let c = 2.2; return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2) }
    static func linear(_ x: Double) -> Double { x }
}

/// A value easing from one number to another over a stretch of time.
struct Tween {
    var from: Double, to: Double, start: Double, duration: Double
    var ease: (Double) -> Double

    init(_ value: Double) { self.init(value, value, at: 0, over: 0) }
    init(_ from: Double, _ to: Double, at start: Double, over duration: Double, _ ease: @escaping (Double) -> Double = Ease.linear) {
        self.from = from; self.to = to; self.start = start; self.duration = duration; self.ease = ease
    }

    func value(_ t: Double) -> Double {
        guard duration > 0, t < start + duration else { return t < start ? from : to }
        return t < start ? from : from + (to - from) * ease((t - start) / duration)
    }

    func done(_ t: Double) -> Bool { t >= start + duration }
}

// MARK: - The view

/// The fuse over the status item's button. It draws every frame while something happens, at 24 fps while only the
/// flame or the smoke moves, and not at all when nothing does. It tells the item how wide to be. Clicks go through to
/// the button.
public final class FuseView: NSView {
    public static let margin = 4.0
    private(set) var scene = FuseScene()
    public var resize: (CGFloat) -> Void = { _ in }
    private var shown = false
    private var link: CADisplayLink?
    private var width: CGFloat = 0

    public func show(_ look: FuseLook) {
        guard !shown || look != scene.look else { return }
        let now = CACurrentMediaTime()
        scene.still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        scene.update(look, at: now, animated: shown)
        shown = true
        needsDisplay = true
        pace(now)
    }

    private func pace(_ t: Double) {
        let w = CGFloat(scene.width(at: t) + 2 * Self.margin)
        if w != width { width = w; resize(w) }
        let busy = scene.busy(at: t)
        guard busy || scene.idling(at: t) else { link?.isPaused = true; return }
        if link == nil {
            link = displayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        link?.preferredFrameRateRange = busy ? .default : CAFrameRateRange(minimum: 12, maximum: 24, preferred: 24)
        link?.isPaused = false
    }

    @objc private func tick() { needsDisplay = true }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    public override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = CACurrentMediaTime()
        ctx.translateBy(x: bounds.width - Self.margin, y: ((bounds.height - 18) / 2).rounded())
        scene.draw(ctx, at: t, ink: NSColor.labelColor.cgColor)
        pace(t)
    }
}

// MARK: - Previews

/// Every state and every move, frame by frame, on a light and a dark menu bar.
public struct FusePreviews: View {
    static let states: [(String, FuseLook)] = [
        ("Not connected", FuseLook(phase: .offline)),
        ("Fresh", FuseLook()),
        ("Warm", FuseLook(left: 0.7)),
        ("Past half", FuseLook(left: 0.45)),
        ("Last third", FuseLook(left: 0.2)),
        ("Fusing", FuseLook(phase: .fusing, left: 0, bangAt: .now.addingTimeInterval(1))),
        ("Boom", FuseLook(phase: .blown)),
        ("Chain reaction", FuseLook(phase: .blown, name: "Chain reaction", tier: 2)),
        ("Meltdown", FuseLook(phase: .blown, name: "Meltdown", tier: 3)),
        ("Still burning", FuseLook(phase: .blown, heat: 0.6)),
        ("Cooled off", FuseLook(phase: .blown, quiet: true)),
    ]

    /// Each move, and how many seconds of it to show.
    static let moves: [(String, FuseLook, FuseLook, Double)] = [
        ("Rated: nothing", FuseLook(prompt: 1, rating: true), FuseLook(prompt: 1), 1),
        ("Rated: heat", FuseLook(left: 0.8, prompt: 1, rating: true), FuseLook(left: 0.45, prompt: 1, bite: 0.35), 6),
        ("Rated: cool", FuseLook(left: 0.45, prompt: 1, rating: true), FuseLook(left: 0.75, prompt: 1), 2.4),
        ("Rated: both", FuseLook(left: 0.7, prompt: 1, rating: true), FuseLook(left: 0.6, prompt: 1, bite: 0.35), 6),
        ("Close call", FuseLook(left: 0.2), FuseLook(left: 0.55), 2.4),
        ("Burn out", FuseLook(left: 0.3), FuseLook(phase: .fusing, left: 0, bangAt: .now.addingTimeInterval(30)), 2),
        ("Slow-mo", FuseLook(phase: .fusing, left: 0, bangAt: .now.addingTimeInterval(30)), FuseLook(phase: .fusing, left: 0, bangAt: .now.addingTimeInterval(1.4)), 1.4),
        ("Bang", FuseLook(phase: .fusing, left: 0, bangAt: .now), FuseLook(phase: .blown), 5),
        ("Chain reaction", FuseLook(phase: .blown, heat: 0.9), FuseLook(phase: .blown, name: "Chain reaction", tier: 2), 1),
        ("Still burning", FuseLook(phase: .blown, quiet: true), FuseLook(phase: .blown, heat: 0.5, quiet: true), 1),
        ("Quiets down", FuseLook(phase: .blown), FuseLook(phase: .blown, quiet: true), 1),
        ("Fresh fuse", FuseLook(phase: .blown, quiet: true), FuseLook(), 2.4),
    ]

    /// Twelve moments of a move `span` seconds long, closer together at the start, where most happens.
    static func frames(_ span: Double) -> [Double] { (0..<12).map { span * pow(Double($0) / 11, 1.6) } }

    /// A whole session, for the menu bar demo: how long to hold each look. Fusing bangs when its hold is up.
    public static let demo: [(Double, FuseLook)] = [
        (2.5, FuseLook()),
        (1, FuseLook(prompt: 1, rating: true)), (2, FuseLook(prompt: 1)), // nothing
        (1, FuseLook(prompt: 2, rating: true)), (5, FuseLook(left: 0.7, prompt: 2, bite: 0.3)), // heat
        (1, FuseLook(left: 0.7, prompt: 3, rating: true)), (3, FuseLook(left: 0.9, prompt: 3)), // cool
        (1, FuseLook(left: 0.9, prompt: 4, rating: true)), (5.5, FuseLook(left: 0.6, prompt: 4, bite: 0.45)), // both
        (1, FuseLook(left: 0.6, prompt: 5, rating: true)), (6.5, FuseLook(left: 0.25, prompt: 5, bite: 0.35)), // the last third
        (1, FuseLook(left: 0.25, prompt: 6, rating: true)), (3, FuseLook(left: 0.5, prompt: 6)), // held it together
        (1, FuseLook(left: 0.5, prompt: 7, rating: true)), (6, FuseLook(phase: .fusing, left: 0)), // it blows
        (9, FuseLook(phase: .blown)), (5, FuseLook(phase: .blown, heat: 0.6)),
        (7, FuseLook(phase: .blown, name: "Chain reaction", tier: 2)), (4, FuseLook(phase: .blown, name: "Chain reaction", tier: 2, quiet: true)),
        (1, FuseLook())]

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([false, true], id: \.self) { dark in
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Self.states, id: \.0) { name, look in
                        VStack(spacing: 4) {
                            FuseFrame(scene: Self.scene(look, look), t: 0.4, dark: dark)
                            Text(name).font(.system(size: 9)).foregroundStyle(dark ? .white : .black)
                        }
                    }
                }
                .padding(10)
                .background(dark ? Color(white: 0.16) : Color(white: 0.93))
            }
            ForEach(Self.moves, id: \.0) { name, from, to, span in
                HStack(spacing: 6) {
                    Text(name).font(.caption).foregroundStyle(.white).frame(width: 96, alignment: .leading)
                    ForEach(Self.frames(span), id: \.self) { t in
                        FuseFrame(scene: Self.scene(from, to), t: t, dark: true, width: 100)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.1))
    }

    /// A scene that's just gone from `from` to `to` at time 0.
    static func scene(_ from: FuseLook, _ to: FuseLook) -> FuseScene {
        var scene = FuseScene()
        scene.update(from, at: -10, animated: false)
        scene.update(to, at: 0)
        return scene
    }
}

/// One frame of a scene, magnified, as wide as the menu bar item would be, or `width`, with the content at the right.
struct FuseFrame: View {
    let scene: FuseScene
    let t: Double
    var dark = false
    var zoom = 2.0
    var width: Double?

    var body: some View {
        let w = width ?? scene.width(at: t) + 2 * FuseView.margin
        Canvas { context, size in
            context.withCGContext { ctx in
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: zoom, y: -zoom)
                ctx.translateBy(x: w - FuseView.margin, y: 3)
                scene.draw(ctx, at: t, ink: dark ? CGColor(gray: 1, alpha: 0.9) : FuseScene.ink)
            }
        }
        .frame(width: w * zoom, height: 24 * zoom)
        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
    }
}

/// Live: press the buttons and watch it move, as it will in the menu bar.
struct FusePlayground: View {
    @State private var scene = FuseScene()
    @State private var look = FuseLook()
    private static let names = ["Boom", "Chain reaction", "Meltdown"]

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation) { context in
                FuseFrame(scene: scene, t: context.date.timeIntervalSinceReferenceDate, dark: true, zoom: 5, width: 110)
            }
            HStack {
                Button("Heat") { go { $0.phase == .lit ? ($0.left = max(0, $0.left - 0.22)) : ($0.heat = min(1, $0.heat + 0.3)) } }
                Button("Cool") { go { $0.phase == .lit ? ($0.left = min(1, $0.left + 0.22)) : ($0.heat = max(0, $0.heat - 0.3)) } }
                Button("Both") { go { $0.prompt = ($0.prompt ?? 0) + 1; $0.bite = 0.3; $0.left = max(0.05, $0.left - 0.1) } }
                Button("Burn out") { go { $0 = FuseLook(phase: .fusing, left: 0, bangAt: .now.addingTimeInterval(3)) } }
                Button("Bang") { go { $0 = FuseLook(phase: .blown) } }
                Button("Tier up") { go { $0.tier = min(3, $0.tier + 1); $0.name = Self.names[$0.tier - 1]; $0.heat = 0; $0.quiet = false } }
                Button("Quiet") { go { $0.quiet.toggle() } }
                Button("Fresh") { go { $0 = FuseLook() } }
            }
        }
        .padding(20)
    }

    private func go(_ change: (inout FuseLook) -> Void) {
        change(&look)
        scene.update(look, at: Date().timeIntervalSinceReferenceDate)
    }
}

#Preview("Fuse states and moves") { FusePreviews() }
#Preview("Fuse playground") { FusePlayground() }
