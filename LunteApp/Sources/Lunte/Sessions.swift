import FuseKit
import LunteCore
import SwiftUI

/// A closed session, opened under its row: the shape of it in one kind line (`Story.arc`), what its aura was for, said
/// plainly, and its fuse in bars. No prompts but your line about its Boom: the rest is history.
// Why: the peak-end rule, told kindly and at a glance (docs/why.md#session-story)
struct SessionCard: View {
    @ObservedObject var model: GameModel
    let sitting: Sitting

    var body: some View {
        let events = model.messages(in: sitting)
        let line = Game.fuseLine(sitting, events, now: Date().timeIntervalSince1970)
        VStack(alignment: .leading, spacing: 3) {
            Text(Story.arc(sitting, line)).foregroundStyle(.secondary)
            if let aura = Story.auraLine(sitting) { Text(aura) } // the reward, so it never hides behind a hover
            SessionChart(story: Array(line.dropLast()), cool: Story.coolStretches(events), boomed: sitting.boom != nil)
                .frame(height: 132).padding(.top, 10)
            if let boom = sitting.boom, let mine = model.justifications[model.litID(boom)] { Text("“\(mine)”").padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The fuse across a session in bars, like Battery's level chart: a bar per slice of the session (2 to 30 minutes, so it
/// gets about 48), as low as the fuse got in it (or as high, once cool grew it past 100 %), with round ends. Grey down
/// to 85 % so a calm session reads calm, green above 100 %, orange as it burns, red in the last third. 0 % is always
/// there, and 125 % only once it got there. Clock hours run underneath. When you were cool shows like Battery's
/// charging: a light overlay on the bars and a line under the axis, with one symbol on the longest. Nothing else is
/// marked: the bars show where it blew.
struct SessionChart: View {
    let story: [(ts: Double, left: Double)] // the fuse line up to its close, a fresh fuse that isn't the story
    let cool: [ClosedRange<Double>]
    let boomed: Bool
    static let margin = 38.0

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .accessibilityElement()
            .accessibilityLabel(summary)
    }

    private func level(_ t: Double) -> Double { story.last { $0.ts <= t }?.left ?? 1 }

    private var summary: String {
        let peak = story.map(\.left).max() ?? 1, low = story.map(\.left).min() ?? 1
        return "The fuse across the session: " + (peak > 1.001 ? "grew to \(Int((peak * 100).rounded(.down))) %, " : "")
            + (boomed ? "then blew" : "lowest \(Int((low * 100).rounded(.down))) %")
            + (cool.isEmpty ? "" : ", cool " + (cool.count == 1 ? "once" : "\(cool.count) times"))
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        guard let first = story.first?.ts, let last = story.last?.ts, last > first else { return }
        let step = [120.0, 300, 600, 900, 1800].first { (last - first) / $0 <= 48 } ?? 1800
        let count = max(1, Int(((last - first) / step).rounded(.up))), end = first + Double(count) * step
        let top = story.contains { $0.left > 1.001 } ? Game.full : 1.0
        let right = size.width - Self.margin, plotTop = 6.0, plotBottom = size.height - 32, marks = plotBottom + 10
        let x = { (t: Double) in (t - first) / (end - first) * right }
        let y = { (l: Double) in plotBottom - l / top * (plotBottom - plotTop) }
        let grid = Color.secondary.opacity(0.35), dotted = StrokeStyle(lineWidth: 1, dash: [1.5, 2.5])
        // The levels, labelled in the margin.
        for (l, label) in [(0.0, "0 %"), (0.5, "50 %"), (1.0, "100 %")] + (top > 1 ? [(Game.full, "125 %")] : []) {
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(l))); $0.addLine(to: CGPoint(x: right, y: y(l))) },
                       with: .color(grid), style: l == 0 ? StrokeStyle(lineWidth: 1) : dotted)
            ctx.draw(Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: size.width, y: y(l)), anchor: .trailing)
        }
        // Clock hours, dotted, labelled underneath; a session inside one hour gets its start time instead.
        let calendar = Calendar.current
        var hour = calendar.nextDate(after: Date(timeIntervalSince1970: first), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
        var labelled = false
        while let h = hour, h.timeIntervalSince1970 < end {
            let hx = x(h.timeIntervalSince1970)
            ctx.stroke(Path { $0.move(to: CGPoint(x: hx, y: plotTop)); $0.addLine(to: CGPoint(x: hx, y: plotBottom)) }, with: .color(grid), style: dotted)
            ctx.draw(Text(String(format: "%02d", calendar.component(.hour, from: h))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                     at: CGPoint(x: hx, y: size.height), anchor: .bottom)
            labelled = true
            hour = calendar.date(byAdding: .hour, value: 1, to: h)
        }
        if !labelled {
            ctx.draw(Text(clock(first)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
        }
        // When you were cool: a light overlay on the bars.
        let lines = cool.map { c in (a: x(max(c.lowerBound, first)), b: max(x(min(c.upperBound, end)), x(max(c.lowerBound, first)) + 4)) }
        for l in lines {
            ctx.fill(Path(CGRect(x: l.a, y: plotTop, width: l.b - l.a, height: plotBottom - plotTop)), with: .color(.green.opacity(0.13)))
        }
        // The bars, round at the ends.
        let width = right / Double(count), gap = width > 5 ? 1.5 : 1.0
        for i in 0..<count {
            let a = first + Double(i) * step, b = a + step
            let levels = [level(a)] + story.filter { $0.ts > a && $0.ts < b }.map(\.left)
            let low = levels.min() ?? 1, v = low < 0.999 ? low : (levels.max() ?? 1)
            guard v > 0.001 else { continue } // blown: nothing left
            // A scratch or two isn't a burn: grey down to 85 %, as `Story.arc` calls it, so a calm session reads calm.
            let color: Color = v > 1.001 ? .green : v >= 0.85 ? .gray.opacity(0.55) : Game.inLastThird(v) ? .red : .orange
            let w = max(1, width - gap)
            ctx.fill(Path(roundedRect: CGRect(x: x(a) + gap / 2, y: y(v), width: w, height: plotBottom - y(v)), cornerRadius: min(w / 2, 3)),
                     with: .color(color.opacity(0.9)))
        }
        // Under the axis, like Battery's charging: a line for each cool stretch, the symbol cut into the longest.
        for l in lines {
            ctx.fill(Path(roundedRect: CGRect(x: l.a, y: marks - 2, width: l.b - l.a, height: 4), cornerRadius: 2), with: .color(.green.opacity(0.8)))
        }
        if let longest = lines.max(by: { $0.b - $0.a < $1.b - $1.a }) {
            var image = ctx.resolve(Image(systemName: "face.smiling.inverse"))
            image.shading = .color(.green)
            let p = CGPoint(x: min(right - 8, max(8, (longest.a + longest.b) / 2)), y: marks), side = 11.0
            let rect = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Color(nsColor: .windowBackgroundColor)))
            ctx.draw(image, in: rect)
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
    @State var picked: Set<Double> = [] // the opened sessions, by start: each opens and closes on its own, so none moves another
    @State private var focus: Double? // the one opened last, to show whole
    @State private var replays: [Double: Double] = [:] // a pill as it replays, by start
    @State private var hovered: Double? // the row the pointer's on, whose pill the breeze runs through
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
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : MenuPanel.expand) { if opened { picked.remove(s.start) } else { picked.insert(s.start) } }
                focus = opened ? nil : s.start
                // The first time it's opened, its pill runs the session back.
                if s.start > model.seen, !reduceMotion {
                    replays[s.start] = 0
                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: SessionFuse.duration(levels, boomed: boomed))) { replays[s.start] = 1 }
                    }
                }
                model.opened(s)
            } label: {
                HStack(spacing: 9) {
                    SessionFuse(levels: levels, boomed: boomed, replay: replays[s.start] ?? (s.start > model.seen ? 0 : 1), // unopened: fresh
                                breeze: hovered == s.start && !reduceMotion)
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                    if s.aura > 0 { Text("+\(s.aura)").monospacedDigit().foregroundStyle(.secondary) }
                    if newest { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(opened ? 90 : 0))
                }
                .modifier(Lit())
                .onHover { hovered = $0 ? s.start : hovered == s.start ? nil : hovered }
            }
            .buttonStyle(.plain)
            .help(Game.sessionLine(s))
            .accessibilityLabel(name + ", " + clock(s.start) + (s.boom != nil ? ", it went boom" : "") + (s.aura > 0 ? ", plus \(s.aura) aura" : ""))
            .accessibilityValue(opened ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(opened ? .isSelected : [])
            if opened { SessionCard(model: model, sitting: s).padding(.top, 2).padding(.bottom, 10) }
        }
        .id(s.start)
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
