import FuseKit
import LunteCore
import SwiftUI

/// A closed session, opened under its row: its heat over the clock in a small line, the prompts that turned it
/// (`Story.moves`) in your own words, each with how far it moved the fuse, and your line about its Boom as your bubble,
/// with the Club's reactions. Pointing along the line glides a hairline after the pointer, the prompts popping up as it
/// passes; pointing at a move glides it there. The text is read from Claude Code's history as it shows, never stored.
// Why: the peak-end rule, told kindly and at a glance (docs/why.md#session-story)
struct SessionCard: View {
    @ObservedObject var model: GameModel
    let sitting: Sitting
    let events: [Event], moves: [Story.Move], now: Double // worked out once, not on every move of the pointer
    @State private var at = 0.0 // the moment pointed at, which the hairline glides after
    @State private var shown = 0.0 // how much the hairline shows
    @State private var holding: Double? // what the pointer's on, so leaving one move for the next doesn't fade it
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: GameModel, sitting: Sitting) {
        self.model = model
        self.sitting = sitting
        events = model.messages(in: sitting)
        now = sitting.end + 3600 // any time after it closed: its ratings are all in
        moves = Story.moves(sitting, events, Game.fuseLine(sitting, events, now: now))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HeatLine(events: events, moves: moves, now: now, at: at, shown: shown, point: point).frame(height: 36).padding(.bottom, 8)
            ForEach(moves, id: \.event.ts) { m in
                HStack(spacing: 8) {
                    Mark(move: m, now: now).frame(width: 12)
                    PromptText(model: model, event: m.event, lines: 1, gone: m.kind.rawValue)
                    Spacer(minLength: 6)
                    if m.kind == .setItOff { Text(tier(sitting.tier).name).foregroundStyle(.secondary) }
                    else {
                        HStack(spacing: 2) {
                            Image(systemName: m.change > 0 ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .semibold))
                            Text("\(Int((abs(m.change) * 100).rounded()))").monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(m.change > 0 ? "grew it" : "burnt") \(Int((abs(m.change) * 100).rounded())) %")
                    }
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .onHover { point($0 ? m.event.ts : nil) }
            }
            if let boom = sitting.boom { Said(model: model, boom: model.litID(boom)).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Glides the hairline to a moment, appearing there if it wasn't showing, or lets it fade once nothing holds it.
    private func point(_ t: Double?) {
        holding = t
        guard let t else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { // the next move's hover may come right after
                if holding == nil { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { shown = 0 } }
            }
            return
        }
        if shown == 0 { at = t } // it appears where you point, rather than sliding in from the last
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) { at = t; shown = 1 }
    }
}

/// A prompt that turned the session: the Boom's burst, or its dot as the live session draws it.
private struct Mark: View {
    let move: Story.Move
    let now: Double

    var body: some View {
        if move.kind == .setItOff { Image(systemName: "burst.fill").font(.system(size: 11)).foregroundStyle(.red) }
        else { Circle().fill(color).frame(width: 9, height: 9).shadow(color: move.kind == .back ? .green.opacity(0.7) : .clear, radius: 2) }
    }

    var color: Color { move.kind == .back ? .green.opacity(0.6) : dotColor(move.event.heat(at: now)) }
}

/// A session's heat as one small line over the clock, an hour at least, so a short one reads short: each prompt's heat
/// a soft rise from the base, grey, then orange, red at the top as the dots go, and cool a soft green dip under it.
/// Its start time, clock hours (dotted, like Battery's) and how many prompts it had run under it (`Hills` draws the
/// line). Pointing along it says when (`point`); at `at` a hairline shows as much as `shown`, with its time, and the
/// prompts near it pop up as their dots, a move as its mark, growing as it comes close.
struct HeatLine: View, Animatable {
    let events: [Event]
    let moves: [Story.Move]
    let now: Double
    var at: Double
    var shown: Double
    var point: (Double?) -> Void = { _ in }
    @State private var width = 0.0

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(at, shown) }
        set { (at, shown) = (newValue.first, newValue.second) }
    }

    /// The session from its first prompt, over an hour at least.
    private var span: (first: Double, last: Double, length: Double) {
        let first = events.first?.ts ?? 0, last = events.last?.ts ?? first
        return (first, last, max(last - first, 3600))
    }

    /// Where a moment sits along a line `width` wide.
    private func x(_ t: Double, _ width: Double) -> Double { 5 + (width - 10) * (t - span.first) / span.length }

    var body: some View {
        // The hills, drawn once; over them only what follows the pointer draws again as it moves.
        Hills(events: events, now: now, span: span).equatable().overlay {
            Canvas { ctx, size in
                guard !events.isEmpty else { return }
                let (first, _, length) = span, base = Hills.base, rise = Hills.rise, dip = Hills.dip
                let x = { (t: Double) in self.x(t, size.width) }, rest = 1 - shown
                let calendar = Calendar.current
                let hhmm = { (t: Double) in let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }
                func label(_ text: String, _ at: Double, _ anchor: UnitPoint = .bottom, _ opacity: Double) {
                    var c = ctx
                    c.opacity = opacity
                    c.draw(Text(text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                           at: CGPoint(x: anchor == .bottom ? min(size.width - 14, max(14, at)) : at, y: size.height), anchor: anchor)
                }
                // When it started, the clock hours, and how many prompts, fading while the hairline shows.
                if rest > 0.01 {
                    label(hhmm(first), 0, .bottomLeading, rest)
                    label(events.count == 1 ? "1 prompt" : "\(events.count) prompts", size.width, .bottomTrailing, rest)
                    var hour = calendar.nextDate(after: Date(timeIntervalSince1970: first), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
                    while let h = hour, h.timeIntervalSince1970 < first + length {
                        let hx = x(h.timeIntervalSince1970)
                        if hx > 44, hx < size.width - 70 { label(String(format: "%02d", calendar.component(.hour, from: h)), hx, .bottom, rest) } // clear of the ends
                        hour = calendar.date(byAdding: .hour, value: 1, to: h)
                    }
                }
                // The hairline, its time, and the prompts near it popping up, the nearest on top.
                guard shown > 0.01 else { return }
                let px = x(at)
                var line = ctx
                line.opacity = shown
                line.stroke(Path { $0.move(to: CGPoint(x: px, y: 0)); $0.addLine(to: CGPoint(x: px, y: base + dip)) },
                            with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                label(hhmm(at), px, .bottom, shown)
                let reach = min(14, max(7, 3 * size.width / Double(events.count))) // closer in where the prompts crowd
                let near = events.indices.map { i in (i, shown * ease(1 - abs(x(events[i].ts) - px) / reach)) }.filter { $0.1 > 0.02 }.sorted { $0.1 < $1.1 }
                let paper = Color(nsColor: .windowBackgroundColor)
                for (i, grow) in near {
                    let e = events[i], heat = e.heat(at: now), cooled = isCool(e) && heat < 0.35
                    let p = CGPoint(x: x(e.ts), y: cooled ? base + dip * (e.cool ?? 0) : base - rise * heat)
                    if let k = moves.firstIndex(where: { $0.event.ts == e.ts }), let mark = ctx.resolveSymbol(id: k) {
                        var c = ctx
                        c.translateBy(x: p.x, y: p.y)
                        c.scaleBy(x: grow, y: grow)
                        c.draw(mark, at: .zero)
                    } else {
                        let r = 4 * grow
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5, width: 2 * r + 3, height: 2 * r + 3)), with: .color(paper))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(cooled ? .green.opacity(0.6) : dotColor(heat)))
                    }
                }
            } symbols: {
                ForEach(Array(moves.enumerated()), id: \.offset) { k, m in
                    Mark(move: m, now: now).padding(1.5).background(Circle().fill(Color(nsColor: .windowBackgroundColor))).tag(k)
                }
            }
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard case .active(let p) = phase, width > 10 else { return point(nil) }
            point(min(span.last, max(span.first, span.first + (p.x - 5) / (width - 10) * span.length)))
        }
        .accessibilityElement()
        .accessibilityLabel("The session's heat over the clock, \(events.count) prompts")
    }

    /// 0 to 1, eased in and out.
    private func ease(_ v: Double) -> Double { let c = min(1, max(0, v)); return c * c * (3 - 2 * c) }
}

/// The heat line's still part: each prompt a soft hill as high as its heat, the line their skyline, so a hot prompt
/// keeps its peak, grey, then orange, red at the top; cool a soft green dip under it; the base, dotted on past its end
/// to the hour; and the clock hours, dotted.
private struct Hills: View, Equatable {
    let events: [Event]
    let now: Double
    let span: (first: Double, last: Double, length: Double)
    static let base = 20.0, rise = 18.0, dip = 4.0

    static func == (a: Self, b: Self) -> Bool { a.now == b.now && a.events == b.events }

    var body: some View {
        Canvas { ctx, size in
            guard !events.isEmpty else { return }
            let (first, last, length) = span, base = Self.base
            let x = { (t: Double) in 5 + (size.width - 10) * (t - first) / length }
            let calendar = Calendar.current
            var hour = calendar.nextDate(after: Date(timeIntervalSince1970: first), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
            while let h = hour, h.timeIntervalSince1970 < first + length {
                let hx = x(h.timeIntervalSince1970)
                ctx.stroke(Path { $0.move(to: CGPoint(x: hx, y: 0)); $0.addLine(to: CGPoint(x: hx, y: base + Self.dip)) },
                           with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
                hour = calendar.date(byAdding: .hour, value: 1, to: h)
            }
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
    @State private var replays: [Double: Double] = [:] // a pill as it replays, by start
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
        }
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
        /// Runs the session back in its pill, after `wait`.
        func replay(after wait: Double = 0) -> Double {
            let d = SessionFuse.duration(levels, boomed: boomed)
            replays[s.start] = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { withAnimation(.linear(duration: d)) { replays[s.start] = 1 } }
            return wait + d
        }
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : MenuPanel.expand) { picked = opened ? [] : [s.start] } // one open at a time
                focus = opened ? nil : s.start
                if !opened, !reduceMotion { _ = replay() } // each time it's opened, its pill runs the session back
                model.opened(s)
            } label: { Pointed { on in
                HStack(spacing: 9) {
                    SessionFuse(levels: levels, boomed: boomed, replay: replays[s.start] ?? (unplayed ? 0 : 1), // unplayed: fresh
                                breeze: on && !reduceMotion)
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                    if s.aura > 0 { Text("+\(s.aura)").monospacedDigit().foregroundStyle(.secondary) }
                    if newest { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(opened ? 90 : 0))
                }
                .modifier(Lit())
            } }
            .buttonStyle(.plain)
            .help(Game.sessionLine(s))
            .accessibilityLabel(name + ", " + clock(s.start) + (s.boom != nil ? ", it went boom" : "") + (s.aura > 0 ? ", plus \(s.aura) aura" : ""))
            .accessibilityValue(opened ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(opened ? .isSelected : [])
            if opened { SessionCard(model: model, sitting: s).padding(.top, 2).padding(.bottom, 10) }
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

/// Whether the pointer's on a row, kept in the row, so moving it from row to row redraws those two rows, not the list.
private struct Pointed<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var on = false

    var body: some View { content(on).onHover { on = $0 } }
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
