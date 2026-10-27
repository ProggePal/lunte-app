import FuseKit
import LunteCore
import SwiftUI

/// A closed session, opened under its row: its heat over the clock in a small line, and one prompt in your own words,
/// in full, with what it did to the fuse: the one its story turned on (`Story.peak`), or one you find along the line.
/// Then your line about its Boom as your bubble, with the Club's reactions. The row's pill rests on the prompt being
/// read, as the fuse was then (a Boom's, on its blast), and runs back to the end once the session's closed.
/// - Opening it, the pill runs the session up to that prompt and the prompts pop up along the line as it passes them,
///   with nothing else to read; the hours, the count and the prompt fade in once it's there, or as soon as you point.
/// - Pointing along the line glides a hairline there and the pill with it; the strongest prompt near it is read once
///   the pointer rests. Let go, and after a beat the pill glides back to the prompt read (closing first snaps it).
/// - A click reads the next prompt down, by what it did, among those around it; nothing else moves.
/// - Dragging out a stretch gives its times and how many prompts it had, and reads its strongest; the hairline steps
///   aside, and the pill rests there.
/// The text is read from Claude Code's history as it opens, never stored.
// Why: the peak-end rule, told kindly and at a glance (docs/why.md#session-story)
struct SessionCard: View {
    @ObservedObject var model: GameModel
    let sitting: Sitting
    @ObservedObject var telling: Telling // how far the row's pill has run the session back
    let events: [Event], impacts: [Double], peak: Int?, now: Double // worked out once, not on every move of the pointer
    let ranking: [Int] // its prompts by what they did, the one that set off a Boom first
    let levels: [Double], times: [Double] // the fuse line, as the pill has it
    @State private var at = 0.0 // the moment pointed at, which the hairline glides after
    @State private var shown = 0.0 // how much the hairline shows
    @State private var picked: Int? // the prompt pointed at: the strongest near the pointer, or in a stretch
    @State private var reading: Int? // the prompt whose words show, once the pointer has rested on it
    @State private var aim: Int? // the prompt to read next, if the pointer stays
    @State private var left: Date? // when the pointer left the line
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: GameModel, sitting: Sitting, telling: Telling) {
        self.model = model
        self.sitting = sitting
        _telling = ObservedObject(wrappedValue: telling)
        (events, now) = (model.messages(in: sitting), sitting.end + 3600) // any time after it closed: its ratings are all in
        let line = Game.fuseLine(sitting, events, now: now)
        impacts = Story.impacts(events, line)
        peak = Story.peak(sitting, events, impacts)
        ranking = Self.ranked(sitting, events, impacts)
        levels = line.dropLast().map(\.left)
        times = line.dropLast().map(\.ts)
        _reading = State(initialValue: peak)
    }

    /// Its prompts by what they did to the fuse, strongest first, the one that set off a Boom before all.
    static func ranked(_ s: Sitting, _ events: [Event], _ impacts: [Double]) -> [Int] {
        events.indices.sorted { a, b in
            (events[a].ts == s.boom?.ts ? 1 : 0, abs(impacts[a]), events[a].cool ?? 0) > (events[b].ts == s.boom?.ts ? 1 : 0, abs(impacts[b]), events[b].cool ?? 0)
        }
    }

    /// Where the pill rests for prompt `i`: the fuse just after it, or a Boom's blast at its end.
    static func rest(_ s: Sitting, _ events: [Event], _ levels: [Double], _ times: [Double], on i: Int?) -> Double {
        guard let i, events[i].ts != s.boom?.ts else { return 1 }
        return max(0.05, SessionFuse.replay(at: events[i].ts, levels, times, boomed: s.boom != nil))
    }

    /// Where the pill comes to rest as the session opens: on its peak.
    static func goal(_ model: GameModel, _ s: Sitting) -> Double {
        let events = model.messages(in: s), line = Game.fuseLine(s, events, now: s.end + 3600)
        let levels = line.dropLast().map(\.left), times = line.dropLast().map(\.ts)
        return rest(s, events, levels, times, on: Story.peak(s, events, Story.impacts(events, line)))
    }

    var body: some View {
        let lead = picked ?? peak, intro = telling.opening ? min(1, (telling.story ?? 1) / telling.goal) : 1
        VStack(alignment: .leading, spacing: 3) {
            HeatLine(events: events, impacts: impacts, reading: reading, boom: sitting.boom?.ts, now: now, at: at, shown: shown,
                     story: telling.story ?? 1, intro: intro, open: model.popoverOpen, point: point, select: select, cycle: cycle) { [levels, times, boomed = sitting.boom != nil] in
                SessionFuse.moment(at: $0, levels, times, boomed: boomed)
            }
            .frame(height: 36 + Hills.top).padding(.top, -Hills.top).padding(.bottom, 6) // its headroom in the gap above
            if let lead {
                // Its dot leads, following the pointer small; the words come in once it rests there, and grow it full.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(dotTint(events[lead], boom: events[lead].ts == sitting.boom?.ts, now: now)).frame(width: 9, height: 9)
                        .scaleEffect(reading == lead ? 1 : 0.55).opacity(reading == lead ? 1 : 0.6)
                    if let i = reading {
                        let e = events[i], change = impacts[i]
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            PromptText(model: model, event: e, lines: 3, gone: Game.heatWord(e.heat(at: now)).capitalized)
                            Spacer(minLength: 6)
                            if e.ts == sitting.boom?.ts { Text(tier(sitting.tier).name).foregroundStyle(.secondary) }
                            else if abs(change) >= 0.005 {
                                HStack(spacing: 2) {
                                    Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .semibold)) // on, in time
                                    Text("\(Int((abs(change) * 100).rounded()))").monospacedDigit()
                                }
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(change > 0 ? "grew it" : "burnt") \(Int((abs(change) * 100).rounded())) %")
                            }
                        }
                        .id(i)
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: reading == lead)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading) // three lines, so pointing along never moves what's under it
                .modifier(Revealed(story: intro))
            }
            if let boom = sitting.boom { Said(model: model, boom: model.litID(boom)).padding(.top, 4).modifier(Revealed(story: intro)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.prefetch(events) }
        // Closed with the pointer still on the line (Escape, another app), it lets go at once: nothing's left showing
        // or moving when it opens again.
        .onChange(of: model.popoverOpen) { _, open in
            guard !open else { return }
            (picked, left, shown) = (nil, nil, 0)
            if aim != peak { (aim, reading) = (peak, peak) }
        }
    }

    /// The pointer along the line, at moment `t`, or gone: the hairline and the pill glide there, and the strongest
    /// prompt near it (`pick`) is read once it rests. Gone, the hairline fades, the story's own prompt comes back, and
    /// after a beat the pill glides back to rest on it.
    private func point(_ t: Double?, _ pick: Int?) {
        guard let t else {
            picked = nil
            settle(on: peak)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { shown = 0 }
            // A beat first, so a pointer on its way to close the session snaps the pill to its end instead.
            let now = Date(), cut = telling.cut
            left = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard left == now, telling.cut == cut, let story = telling.story else { return } // closed since: it stays at its end
                let goal = Self.rest(sitting, events, levels, times, on: peak)
                // At the pace it's told when it opens, so it doesn't rush, but never long.
                let way = abs(goal - story) * SessionFuse.duration(levels, boomed: sitting.boom != nil)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: min(1.6, max(0.5, way)))) { telling.story = goal }
            }
            return
        }
        left = nil
        picked = pick
        settle(on: pick)
        if shown == 0 { at = t } // it appears where you point, rather than sliding in from the last
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
            at = t
            shown = 1
            telling.opening = false
            telling.story = SessionFuse.replay(at: t, levels, times, boomed: sitting.boom != nil)
        }
    }

    /// A stretch of the session dragged out, by its moments, `done` once it's let go, or nil once it's gone: the hairline
    /// steps aside, the strongest prompt in it is read (once the pointer rests, or at once when it's let go), and the
    /// pill rests on it.
    private func select(_ stretch: ClosedRange<Double>?, done: Bool) {
        left = nil
        guard let stretch else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { shown = 0 }
        guard let best = ranking.first(where: { stretch.contains(events[$0].ts) }) else { return }
        picked = best
        if done { aim = best; withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) { reading = best } } else { settle(on: best) }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
            telling.opening = false
            telling.story = Self.rest(sitting, events, levels, times, on: best)
        }
    }

    /// A click among the prompts in `area`: reads the next one down from the one showing, by what it did, round to the
    /// strongest again. The hairline and the pill stay where they are.
    private func cycle(in area: ClosedRange<Double>) {
        let around = ranking.filter { area.contains(events[$0].ts) }
        guard let first = around.first else { return }
        let next = around.firstIndex(of: reading ?? picked ?? -1).map { around[($0 + 1) % around.count] } ?? first
        picked = next
        aim = next
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) { reading = next }
    }

    /// Reads `target` once the pointer has rested on it a moment: what was there steps aside at once, so scrubbing
    /// past prompts never pulls the eye down to their words.
    private func settle(on target: Int?) {
        guard target != aim else { return }
        aim = target
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { reading = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard aim == target else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) { reading = target }
        }
    }
}

/// A prompt's dot: red for the one that set off a Boom, else as the live session draws it.
private func dotTint(_ e: Event, boom: Bool, now: Double) -> Color {
    boom ? .red : isCool(e) && e.heat(at: now) < 0.35 ? .green.opacity(0.6) : dotColor(e.heat(at: now))
}

/// Held back while a session's story is told on opening (`story` below 1), fading in over its last moments.
private struct Revealed: ViewModifier, Animatable {
    var story: Double
    var animatableData: Double { get { story } set { story = newValue } }

    func body(content: Content) -> some View { content.opacity(story < 1 ? max(0, 1 - (1 - story) * 20) : 1) }
}

/// A session's heat as one small line over the clock, an hour at least, so a short one reads short: each prompt's heat
/// a soft rise from the base, grey, then orange, red at the top as the dots go, and cool a soft green dip under it
/// (`Hills`). Under it, dotted clock hours like Battery's, its start time, and how many prompts it had; the prompt being
/// read (`reading`) sits on it as its dot. While the story is told on opening (`intro` below 1) only the prompts pop up,
/// as the pill passes them (`story`, at `moment`); the rest fades in at its end. Pointing along it gives a moment and
/// the strongest prompt near it (`point`); at `at` a hairline shows as much as `shown`, glowing faintly where it ran
/// hot or cool, and the prompts near it pop up, growing as it comes close.
struct HeatLine: View, Animatable {
    let events: [Event]
    let impacts: [Double]
    let reading: Int?
    let boom: Double?
    let now: Double
    var at: Double
    var shown: Double
    var story = 1.0
    var intro = 1.0
    var open = true // the popover's open: closed, nothing draws again
    var point: (Double?, Int?) -> Void = { _, _ in }
    var select: (ClosedRange<Double>?, Bool) -> Void = { _, _ in } // a stretch dragged out, by its moments; done once let go
    var cycle: (ClosedRange<Double>) -> Void = { _ in } // a click, among the prompts in these moments
    var moment: (Double) -> Double = { $0 }
    @State private var width = 0.0
    @State private var band: ClosedRange<Double>? // the stretch being dragged out
    var stretch: ClosedRange<Double>? = nil // ponytail: the lab's stretch, for its stills
    @State private var held: Double? // where a click or a stretch was let go, which holds till the pointer moves on
    @State private var pops = Pops()
    @State private var rested = false // flipped once the dots settle, so the frames stop

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(at, shown), AnimatablePair(story, intro)) }
        set { (at, shown, story, intro) = (newValue.first.first, newValue.first.second, newValue.second.first, newValue.second.second) }
    }

    /// The session from its first prompt, over an hour at least.
    private var span: (first: Double, last: Double, length: Double) {
        let first = events.first?.ts ?? 0, last = events.last?.ts ?? first
        return (first, last, max(last - first, 3600))
    }

    /// Where a moment sits along a line `width` wide.
    private func x(_ t: Double, _ width: Double) -> Double { 5 + (width - 10) * (t - span.first) / span.length }

    var body: some View {
        let _ = rested
        let _ = wake()
        // The hills, drawn once; over them only what moves draws again.
        Hills(events: events, now: now, span: span).equatable().overlay {
            // Frames only while something moves: the pointer's there, the story's being told, or a dot's still changing.
            TimelineView(.animation(paused: !open || !(shown > 0.01 || intro < 1 || pops.moving))) { timeline in
            Canvas { ctx, size in
                guard !events.isEmpty else { return }
                let (first, _, length) = span, base = Hills.base, rise = Hills.rise, dip = Hills.dip
                let x = { (t: Double) in self.x(t, size.width) }, calendar = Calendar.current
                let pointing = shown > 0.01, reveal = pointing || intro >= 1 ? 1 : max(0, 1 - (1 - intro) * 20)
                var quiet = ctx
                quiet.opacity = reveal
                func label(_ text: String, _ at: Double, _ anchor: UnitPoint = .bottom) {
                    quiet.draw(Text(text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                               at: CGPoint(x: anchor == .bottom ? min(size.width - 14, max(14, at)) : at, y: size.height), anchor: anchor)
                }
                let hhmm = { (t: Double) in let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }
                // When it started, the clock hours, and how many prompts. For a stretch dragged out, how many in it, where
                // the count always is, and from when to when, under it, kept clear of the count.
                if let band = band ?? stretch {
                    let small = { (t: String) in quiet.resolve(Text(t).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)) }
                    let n = events.filter { band.contains(x($0.ts)) }.count
                    let count = small(n == 1 ? "1 prompt" : "\(n) prompts")
                    let when = small("\(hhmm(moment(at: band.lowerBound, size.width)))–\(hhmm(moment(at: band.upperBound, size.width)))")
                    let (cw, ww) = (count.measure(in: size).width, when.measure(in: size).width)
                    let mid = min(size.width - cw - 8 - ww / 2, max(ww / 2, (band.lowerBound + band.upperBound) / 2))
                    quiet.draw(count, at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
                    quiet.draw(when, at: CGPoint(x: mid, y: size.height), anchor: .bottom)
                } else {
                    let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: first))
                    label(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0), 0, .bottomLeading)
                    label(events.count == 1 ? "1 prompt" : "\(events.count) prompts", size.width, .bottomTrailing)
                }
                var hour = calendar.nextDate(after: Date(timeIntervalSince1970: first), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
                while let h = hour, h.timeIntervalSince1970 < first + length {
                    let hx = x(h.timeIntervalSince1970)
                    quiet.stroke(Path { $0.move(to: CGPoint(x: hx, y: Hills.top)); $0.addLine(to: CGPoint(x: hx, y: base + dip)) },
                                 with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
                    if hx > 44, hx < size.width - 70, band ?? stretch == nil { label(String(format: "%02d", calendar.component(.hour, from: h)), hx) } // clear of the ends
                    hour = calendar.date(byAdding: .hour, value: 1, to: h)
                }
                // A prompt's dot where it sits on the line, as big as `grow`, ringed so it reads over the hills; small,
                // it fades, ring and all, so a shrinking one never reads as a ring.
                let paper = Color(nsColor: .windowBackgroundColor)
                func dot(_ i: Int, _ grow: Double) {
                    let e = events[i], heat = e.heat(at: now), cooled = isCool(e) && heat < 0.35, r = 4 * grow, ring = 1.5 * grow
                    let p = CGPoint(x: x(e.ts), y: cooled ? base + dip * (e.cool ?? 0) : base - rise * heat)
                    var c = ctx
                    c.opacity = min(1, 2 * grow)
                    c.fill(Path(ellipseIn: CGRect(x: p.x - r - ring, y: p.y - r - ring, width: 2 * (r + ring), height: 2 * (r + ring))), with: .color(paper))
                    c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(dotTint(e, boom: e.ts == boom, now: now)))
                }
                // The pointer's hairline, or as the story's told, just the prompts popping up as it passes them.
                let telling = intro < 1 && !pointing ? min(1, (1 - intro) * 20) : 0
                var near: [Int: Double] = [:]
                if pointing || telling > 0.01 {
                    let px = min(size.width - 1, x(pointing ? at : moment(story))), strength = pointing ? shown : telling
                    if pointing {
                        let hairline = Path { $0.move(to: CGPoint(x: px, y: Hills.top)); $0.addLine(to: CGPoint(x: px, y: base + dip)) }
                        // A faint glow where it runs hot, or was cool: the line's own skyline there.
                        let spread = min(9, max(4, size.width / Double(events.count)))
                        let there = { (v: (Event) -> Double) in events.reduce(0.0) { max($0, v($1) * exp(-pow((x($1.ts) - px) / spread, 2))) } }
                        let hot = there { $0.heat(at: now) }, cool = there { isCool($0) ? $0.cool ?? 0 : 0 }
                        let glow = hot >= 0.35 ? (hot >= 0.85 ? Color.red : .orange, (hot - 0.25) * 0.6) : (Color.green, cool >= Game.coolPrompt ? cool * 0.4 : 0)
                        if glow.1 > 0 {
                            var g = ctx
                            g.opacity = shown * glow.1
                            g.addFilter(.blur(radius: 2.5))
                            g.stroke(hairline, with: .color(glow.0), lineWidth: 3)
                        }
                        var line = ctx
                        line.opacity = shown
                        line.stroke(hairline, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    }
                    let reach = min(14, max(7, 3 * size.width / Double(events.count))) // closer in where the prompts crowd
                    for i in events.indices {
                        let grow = strength * ease(1 - abs(x(events[i].ts) - px) / reach)
                        if grow > 0 { near[i] = grow }
                    }
                }
                if let reading { near[reading] = max(near[reading] ?? 0, reveal) } // the prompt read under the line, full
                for (i, grow) in pops.step(to: timeline.date, near).sorted(by: { $0.value < $1.value }) { dot(i, grow) }
                if pops.settledNow { DispatchQueue.main.async { rested.toggle() } }
            }
            }
        }
        .overlay(alignment: .topLeading) {
            // A stretch dragged out: a soft band over the line, gone once let go.
            if let band = band ?? stretch {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                    .frame(width: max(2, band.upperBound - band.lowerBound), height: Hills.base + Hills.dip + 2 - Hills.top)
                    .offset(x: band.lowerBound, y: Hills.top)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard case .active(let p) = phase, width > 10, !events.isEmpty else { letGo(); return point(nil, nil) }
            if let h = held { if abs(p.x - h) < 12 { return }; letGo() } // what you chose stays till you move on
            point(moment(at: p.x, width), pick(near: p.x))
        }
        // A click reads the next prompt down among those around it, or in the stretch; a stretch dragged out gives its
        // times and count, and reads its strongest.
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard abs(v.translation.width) > 3, width > 10, !events.isEmpty else { return }
                let on = { (px: CGFloat) in min(x(span.last, width), max(x(span.first, width), Double(px))) } // on the session, never past it
                let stretch = min(on(v.startLocation.x), on(v.location.x))...max(on(v.startLocation.x), on(v.location.x))
                NSCursor.resizeLeftRight.set() // it sits on the line, so the times under it stay in view
                band = stretch
                select(moments(stretch), false)
            }
            .onEnded { v in
                NSCursor.arrow.set()
                held = v.location.x
                if let band, abs(v.translation.width) > 3 { return select(moments(band), true) }
                cycle(band.map(moments) ?? moments(v.location.x - reach...v.location.x + reach))
            })
        .onChange(of: open) { _, open in if !open { (band, held) = (nil, nil) } }
        .accessibilityElement()
        .accessibilityLabel("The session's heat over the clock, \(events.count) prompts")
    }

    /// The moment at `px` along a line `width` wide, within the session.
    private func moment(at px: Double, _ width: Double) -> Double {
        min(span.last, max(span.first, span.first + (px - 5) / (width - 10) * span.length))
    }

    /// A stretch of the line as moments.
    private func moments(_ xs: ClosedRange<Double>) -> ClosedRange<Double> { moment(at: xs.lowerBound, width)...moment(at: xs.upperBound, width) }

    /// How near the pointer a prompt pops up, and is in reach of a click: closer in where the prompts crowd.
    private var reach: Double { min(14, max(7, 3 * width / Double(max(1, events.count)))) }

    /// A stretch let go of, or a click's hold, once the pointer moves on: the band fades and the hairline's back.
    private func letGo() {
        held = nil
        guard band != nil else { return }
        withAnimation(.easeOut(duration: 0.3)) { band = nil }
        select(nil, false)
    }

    /// The prompt to read at `px`: the one that moved the fuse most within reach, else the nearest.
    private func pick(near px: Double) -> Int? {
        let within = events.indices.filter { abs(x(events[$0].ts, width) - px) <= reach }
        if let strongest = within.max(by: { abs(impacts[$0]) < abs(impacts[$1]) }), abs(impacts[strongest]) >= 0.02 { return strongest }
        return events.indices.min { abs(x(events[$0].ts, width) - px) < abs(x(events[$1].ts, width) - px) }
    }

    /// 0 to 1, eased in and out.
    private func ease(_ v: Double) -> Double { let c = min(1, max(0, v)); return c * c * (3 - 2 * c) }

    /// A new prompt to read wakes the dots' clock, so its dot grows in; it stops once they settle, and 1.6 s on at the
    /// latest, so it can never be left running.
    private func wake() {
        guard pops.expect(reading) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { pops.rest(); rested.toggle() }
    }
}

/// The dots popping up along a heat line, each growing toward how close the line is to it and shrinking once it's
/// passed, over time, so one the line lingers by grows full and one it sweeps past only swells a little.
final class Pops {
    private var size: [Int: Double] = [:]
    private var last: Date?
    private var reading: Int?
    private(set) var moving = false // a dot is still growing or fading
    private(set) var settledNow = false // they've just come to rest

    /// A new prompt to read wakes the dots, so its own grows in: true if it did.
    func expect(_ reading: Int?) -> Bool {
        guard reading != self.reading else { return false }
        self.reading = reading
        moving = true
        return true
    }

    /// They've settled, whatever the last frame said.
    func rest() { moving = false }

    func step(to now: Date, _ targets: [Int: Double]) -> [Int: Double] {
        let dt = min(0.05, max(0, now.timeIntervalSince(last ?? now)))
        last = now
        var still = true
        for i in Set(size.keys).union(targets.keys) {
            let target = targets[i] ?? 0, was = size[i] ?? 0
            let next = was + (target - was) * (1 - exp(-dt / (target > was ? 0.14 : 0.2))) // grows a touch quicker than it fades
            if abs(next - target) > 0.005 { still = false }
            size[i] = next > 0.01 || target > 0 ? next : nil
        }
        settledNow = moving && still
        moving = !still
        return size
    }
}

/// The heat line's still part: each prompt a soft hill as high as its heat, the line their skyline, so a hot prompt
/// keeps its peak, grey, then orange, red at the top; cool a soft green dip under it; and the base, dotted on past its
/// end to the hour.
private struct Hills: View, Equatable {
    let events: [Event]
    let now: Double
    let span: (first: Double, last: Double, length: Double)
    static let top = 6.0, base = top + 20, rise = 18.0, dip = 4.0 // room over the tallest hill, so its dot isn't cut off

    static func == (a: Self, b: Self) -> Bool { a.now == b.now && a.events == b.events }

    var body: some View {
        Canvas { ctx, size in
            guard !events.isEmpty else { return }
            let (first, last, length) = span, base = Self.base
            let x = { (t: Double) in 5 + (size.width - 10) * (t - first) / length }
            let width = min(9, max(4, size.width / Double(events.count)))
            func area(_ value: (Event) -> Double, _ height: Double) -> Path {
                let hills = events.map { (x: x($0.ts), v: value($0)) }.filter { $0.v > 0.001 }
                return Path { p in
                    p.move(to: CGPoint(x: 0, y: base))
                    for px in stride(from: 0.0, through: size.width, by: 1) {
                        let v = hills.reduce(0.0) { abs(px - $1.x) > 3 * width ? $0 : max($0, $1.v * exp(-pow((px - $1.x) / width, 2))) }
                        p.addLine(to: CGPoint(x: px, y: base - height * v))
                    }
                    p.addLine(to: CGPoint(x: size.width, y: base))
                    p.closeSubpath()
                }
            }
            ctx.fill(area({ isCool($0) ? $0.cool ?? 0 : 0 }, -Self.dip), with: .color(.green.opacity(0.45)))
            let grey = Color.secondary.opacity(0.45)
            ctx.fill(area({ $0.heat(at: now) }, Self.rise), with: .linearGradient(
                Gradient(stops: [.init(color: grey, location: 0), .init(color: grey, location: 0.3), .init(color: .orange, location: 0.4),
                                 .init(color: .orange, location: 0.78), .init(color: .red, location: 0.9)]),
                startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: base - Self.rise)))
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: base)); $0.addLine(to: CGPoint(x: x(last), y: base)) },
                       with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x(last), y: base)); $0.addLine(to: CGPoint(x: size.width, y: base)) },
                       with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
        }
    }
}

/// Your earlier sessions, under the open one: today's in a section of their own, a row each, and the ones before behind
/// Previously, a row that opens like Other Networks in Wi-Fi, onto a list by day that scrolls. A row opens its session
/// under it. It's read from the log on this Mac and never sent, and it never adds up how long you worked.
// Why: your history is yours, never a score of your work (docs/why.md#history-not-a-score)
struct History: View {
    @ObservedObject var model: GameModel
    let sessions: [Sitting] // oldest first
    @State var open = false
    @State var picked: Set<Double> = [] // the opened session, by start: one at a time, so the panel never fills with them
    @State private var focus: Double? // the one opened last, to show whole
    @State private var tellings = Tellings() // each session's replay, which only its pill and card watch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let today = sessions.filter { Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.start)) }
        let before = sessions.filter { !Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.start)) }
        if !today.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Today").fontWeight(.medium).foregroundStyle(.secondary)
                // Three rows, then it scrolls; more room while one of them is open.
                Capped(cap: today.contains { picked.contains($0.start) } ? 380 : 3 * 26 + 2 * 8 + 6, focus: focus) {
                    ForEach(today.reversed(), id: \.start) { row($0) }
                }
            }
            .onChange(of: model.popoverOpen) { _, open in if !open { collapse() } }
        }
        if !before.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(reduceMotion ? nil : MenuPanel.expand) { open.toggle() } } label: {
                    HStack {
                        Text("Previously").fontWeight(.medium).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .modifier(Lit())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                if open {
                    // ponytail: every session in the log, built at once; page it once that's slow
                    Capped(cap: before.contains { picked.contains($0.start) } ? 380 : 240, focus: focus) { // room for an open one
                        ForEach(days(before), id: \.day) { day in
                            Text(header(day.day)).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                            ForEach(day.sessions, id: \.start) { row($0) }
                        }
                    }
                }
            }
            .onChange(of: model.popoverOpen) { _, open in if !open { collapse() } }
        }
    }

    /// Closes every session and Previously as the popover closes, so it always opens collapsed, as the system's own
    /// menus start fresh. Each section asks, so it's done twice when both are there, which changes nothing.
    private func collapse() {
        for start in picked { tellings.of(start).still() }
        (picked, focus, open) = ([], nil, false)
    }

    /// Newest day first, and newest session first within it.
    private func days(_ sessions: [Sitting]) -> [(day: Date, sessions: [Sitting])] {
        Dictionary(grouping: sessions.reversed()) { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: $0.start)) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    /// "Yesterday", or the weekday and date.
    private func header(_ day: Date) -> String {
        Calendar.current.isDateInYesterday(day) ? "Yesterday" : day.formatted(.dateTime.weekday(.wide).day().month())
    }

    /// A session as a row, like a network in Wi-Fi: its own fuse in a pill, its name, the aura it earned, a dot while
    /// the newest waits to be opened, and a chevron that turns as it opens, with the session under it.
    private func row(_ s: Sitting) -> some View {
        let opened = picked.contains(s.start), name = model.names[s.start] ?? "Session"
        let newest = s.start == sessions.last?.start && s.start > model.seen
        let levels = Game.fuseLine(s, model.messages(in: s), now: Date().timeIntervalSince1970).dropLast().map(\.left), boomed = s.boom != nil
        let unplayed = s.start > model.played && Calendar.current.isDateInToday(Date(timeIntervalSince1970: s.start)) && !reduceMotion
        let telling = tellings.of(s.start)
        /// Runs the session back in its pill, after `wait`, up to `goal`.
        func replay(after wait: Double = 0, to goal: Double = 1) -> Double {
            let d = SessionFuse.duration(levels, boomed: boomed) * goal, cut = telling.cut
            telling.goal = goal
            telling.story = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                guard telling.cut == cut else { return } // closed before it began
                withAnimation(.linear(duration: d)) { telling.story = goal }
            }
            return wait + d
        }
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                // Closed, a session stops where it is and its pill snaps to its end: nothing more moves.
                for start in picked { tellings.of(start).still() }
                withAnimation(reduceMotion ? nil : MenuPanel.expand) { picked = opened ? [] : [s.start] } // one open at a time
                focus = opened ? nil : s.start
                // Each time it's opened, its pill runs the session back, up to the prompt it opens on.
                if !opened, !reduceMotion { telling.opening = true; _ = replay(to: SessionCard.goal(model, s)) }
                model.opened(s)
            } label: {
                HStack(spacing: 9) {
                    Told(telling: telling, levels: levels, boomed: boomed, unplayed: unplayed)
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                    if s.aura > 0 { Text("+\(s.aura)").monospacedDigit().foregroundStyle(.secondary) }
                    if newest { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(opened ? 90 : 0))
                }
                .modifier(Lit())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name + ", " + clock(s.start) + (s.boom != nil ? ", it went boom" : "") + (s.aura > 0 ? ", plus \(s.aura) aura" : ""))
            .accessibilityValue(opened ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(opened ? .isSelected : [])
            if opened {
                SessionCard(model: model, sitting: s, telling: telling).padding(.top, 2).padding(.bottom, 10)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity)) // closed, it's gone at once, nothing playing on
            }
        }
        .id(s.start)
        // Not yet watched, it runs back once at your next look, a beat after the popover opens. Closed before its end,
        // it runs back again next time.
        // Why: the session's story is there when you next look (docs/why.md#session-replay)
        .onChange(of: model.popoverOpen) { _, open in
            guard open, unplayed else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + replay(after: 0.3)) { if model.popoverOpen { model.played(s) } }
        }
    }
}

/// How far a session's pill has run it back, 0 to 1, or nil at rest. Only its pill and its opened card watch it, so
/// pointing along the card's line redraws those two, never the list.
final class Telling: ObservableObject {
    @Published var story: Double?
    @Published var opening = false // told as the session opens, so its card holds back all but the line till it's done
    @Published var goal = 1.0 // where the story stops as it opens: on its peak
    @Published private(set) var cut = 0 // a fresh pill, so a replay on its way doesn't carry on

    /// Stops the replay where it is and puts the pill at its end, with no motion.
    func still() {
        var now = Transaction()
        now.disablesAnimations = true
        withTransaction(now) { cut += 1; story = 1; opening = false; goal = 1 }
    }
}

/// Each session's `Telling`, made the first time it's asked for.
final class Tellings {
    private var all: [Double: Telling] = [:]

    func of(_ start: Double) -> Telling {
        if let t = all[start] { return t }
        let t = Telling()
        all[start] = t
        return t
    }
}

/// A session's pill, as far as its `Telling` has run it.
private struct Told: View {
    @ObservedObject var telling: Telling
    let levels: [Double], boomed: Bool, unplayed: Bool

    var body: some View {
        SessionFuse(levels: levels, boomed: boomed, replay: telling.story ?? (unplayed ? 0 : 1)) // unplayed: fresh
            .id(telling.cut)
            .transaction(value: telling.cut) { $0.animation = nil } // stilled: it jumps to its end, with no fade or replay
    }
}

/// A list as tall as it is, up to `cap`, then it scrolls, with no scroller and soft ends, growing and shrinking with the
/// panel. An opened session stays where you clicked it, and the list scrolls only as far as it takes to show all of it.
/// It reaches a little past the sides, so the rows' light fits.
private struct Capped<Content: View>: View {
    let cap: CGFloat
    var focus: Double? = nil
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) { content }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                        withAnimation(height == 0 ? nil : MenuPanel.expand) { height = new } // the first measure lands at once
                    }
            }
            .onChange(of: focus) { _, row in
                guard let row else { return }
                // Once it has opened: no anchor scrolls the least it takes to show it whole, and nothing if it's in view.
                DispatchQueue.main.asyncAfter(deadline: .now() + MenuPanel.resize) {
                    withAnimation(reduceMotion ? nil : MenuPanel.expand) { proxy.scrollTo(row, anchor: nil) }
                }
            }
        }
        .scrollIndicators(.never)
        .modifier(EdgeFade())
        .frame(height: min(height, cap))
        .padding(.horizontal, -7)
    }
}
