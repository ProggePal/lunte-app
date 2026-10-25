import FuseKit
import LunteCore
import SwiftUI

/// A closed session: one fact per line (how long it ran, what happened, how it ended, your line about its Boom, what it
/// earned), then the fuse across it. Point at the fuse and the facts give way to that moment: the time and what was
/// left. No prompts, but the one that set off the Boom, once you point past it: the rest is history.
/// The one you just finished has the title row on top: a fresh fuse's 100 %, or what was left where you point.
// Why: the peak-end rule; a session is remembered by its peak and its end (docs/why.md#summary-next-open)
struct SummaryCard: View {
    @ObservedObject var model: GameModel
    let sitting: Sitting
    var latest = false
    @State private var at: Double? // the moment pointed at

    var body: some View {
        let events = model.messages(in: sitting), now = Date().timeIntervalSince1970
        let line = Game.fuseLine(sitting, events, now: now)
        let left = at.flatMap { t in line.last { $0.ts <= t }?.left }
        let blown = at.flatMap { t in sitting.boom.map { t >= $0.ts } } ?? false
        VStack(alignment: .leading, spacing: 6) {
            if latest {
                TitleRow(trailing: blown ? tier(sitting.tier).name : percent(left ?? 1))
            }
            ZStack(alignment: .topLeading) { // as tall as the taller of the two, so pointing never jumps
                facts.opacity(at == nil ? 1 : 0)
                if let at, let left { moment(at, left: left, blown: blown, events) }
            }
            FuseGraph(line: line, boom: sitting.boom, cooled: sitting.lastBurn.map { $0 + Game.cooling }, at: $at)
                .frame(height: 78)
        }
    }

    private var facts: some View {
        let aura = Game.aura(sitting)
        return VStack(alignment: .leading, spacing: 2) {
            Text(latest ? "Last session · " + length(sitting) : length(sitting)).foregroundStyle(.secondary)
            // One sentence a line: "Slow burn." "Boomed at 14:12." "Cooled off by 14:40."
            ForEach(Game.sessionLine(sitting).replacingOccurrences(of: ". ", with: ".\n").split(separator: "\n").map(String.init), id: \.self) {
                Text($0).foregroundStyle(.secondary)
            }
            if let boom = sitting.boom, let mine = model.justifications[model.litID(boom)] { Text("“\(mine)”") }
            // ponytail: no Club named, since nothing sends aura there yet; that comes with Leagues
            if aura > 0 { Text("+\(aura) aura").fontWeight(.medium) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A moment in the session: the time and what was left; from the Boom on, its tier and the prompt that set it off.
    private func moment(_ t: Double, left: Double, blown: Bool, _ events: [Event]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clock(t) + " · " + (blown ? tier(sitting.tier).name : percent(left))).monospacedDigit().foregroundStyle(.secondary)
            if blown, let boom = sitting.boom, let e = events.first(where: { $0.ts == boom.ts }) { PromptText(model: model, event: e) }
        }
    }
}

/// The fuse across a session, in steps: full at the top, empty at the bottom. A hot prompt drops it at once, and it
/// steps back up when that burn cools off, 30 minutes on. Grey while full, orange while burning, red in the last third
/// and from the Boom, where its emoji sits, until the last burn has cooled off; then grey to the close, where a fresh
/// fuse comes in. No dots: those are for the open session. Time runs at one hour to the full width, so sessions compare
/// at a glance; a longer one scrolls, opening on the Boom or the fuse's lowest point, and a pinch zooms, out to the whole session.
struct FuseGraph: View {
    let line: [(ts: Double, left: Double)]
    let boom: Boom?
    let cooled: Double? // when the last burn cooled off
    @Binding var at: Double?
    @State private var zoom: CGFloat = 1 // 1: an hour to the full width
    @State private var settled: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let span = max(60, (line.last?.ts ?? 0) - (line.first?.ts ?? 0))
            let fit = 3600 / span, width = geo.size.width * zoom / fit
            // Opens on what happened: the Boom, else where the fuse got lowest, else the end.
            let focus = boom?.ts ?? line.min { $0.left < $1.left }.flatMap { $0.left < 1 ? $0.ts : nil } ?? line.last?.ts ?? 0
            ScrollView(.horizontal, showsIndicators: false) {
                canvas.frame(width: width, height: geo.size.height)
            }
            .defaultScrollAnchor(UnitPoint(x: (focus - (line.first?.ts ?? 0)) / span, y: 0.5))
            .gesture(MagnifyGesture()
                .onChanged { zoom = min(max(fit, 4), max(min(fit, 1), settled * $0.magnification)) }
                .onEnded { _ in settled = zoom })
            .help("Pinch to zoom")
        }
        .accessibilityHidden(true)
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard let first = line.first?.ts, let last = line.last?.ts, last > first else { return }
                let plot = size.height - 14 // the clock times go under it
                let x = { (t: Double) in (t - first) / (last - first) * size.width }
                let y = { (left: Double) in 2 + (1 - left) * (plot - 4) }
                // A clock time every quarter, half or whole hour, whichever leaves room between them.
                let step = [900.0, 1800, 3600, 7200].first { $0 / (last - first) * size.width >= 56 } ?? 7200
                var tick = (first / step).rounded(.up) * step
                while tick <= last {
                    ctx.draw(Text(clock(tick)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary), at: CGPoint(x: x(tick), y: size.height), anchor: .bottom)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x(tick), y: plot - 3)); $0.addLine(to: CGPoint(x: x(tick), y: plot)) }, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                    tick += step
                }
                let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                // Blown and cooled off: quiet again, though still empty.
                let color = { (left: Double, t: Double) in left == 0 && t >= (cooled ?? .infinity) ? Color.secondary : fuseColor(left) }
                // Flat until the next change, then the step in the colour of its lower side; the fresh fuse at the close
                // after a Boom, dashed.
                var segments: [(to: CGPoint, color: Color)] = [], fresh: (CGPoint, CGPoint)?
                for (a, b) in zip(line, line.dropFirst()) {
                    let corner = CGPoint(x: x(b.ts), y: y(a.left)), end = CGPoint(x: x(b.ts), y: y(b.left))
                    segments.append((corner, color(a.left, a.ts)))
                    guard a.left != b.left else { continue }
                    if b.ts == last && a.left == 0 { fresh = (corner, end) } else { segments.append((end, color(min(a.left, b.left), b.ts))) }
                }
                // One path per run of one colour, so the see-through grey never doubles up where pieces meet.
                var from = CGPoint(x: 0, y: y(line[0].left)), i = 0
                while i < segments.count {
                    let ink = segments[i].color
                    var path = Path()
                    path.move(to: from)
                    while i < segments.count, segments[i].color == ink { path.addLine(to: segments[i].to); from = segments[i].to; i += 1 }
                    ctx.stroke(path, with: .color(ink), style: stroke)
                }
                if let (a, b) = fresh {
                    ctx.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                }
                if let boom {
                    ctx.draw(Text(tier(boom.tier).emoji.last.map(String.init) ?? "💥").font(.system(size: 11)), at: CGPoint(x: x(boom.ts), y: y(0) - 8))
                }
                if let at {
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x(at), y: 0)); $0.addLine(to: CGPoint(x: x(at), y: plot)) },
                               with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard case .active(let p) = phase, let first = line.first?.ts, let last = line.last?.ts else { return at = nil }
                at = first + max(0, min(1, p.x / geo.size.width)) * (last - first)
            }
        }
    }
}

/// How long a session ran, first message to last: "under a minute", "40 min", "2 h 5 min".
func length(_ s: Sitting) -> String {
    let m = Int((s.end - s.start) / 60)
    return m < 1 ? "under a minute" : m < 60 ? "\(m) min" : "\(m / 60) h" + (m % 60 > 0 ? " \(m % 60) min" : "")
}

/// Your earlier sessions, under the open one: today's in a section of their own, a row each, and the ones before behind
/// Previously, a row that opens like Other Networks in Wi-Fi, onto a list by day that scrolls. Click a session to see
/// its summary again. It's read from the log on this Mac and never sent, and it never adds up how long you worked.
// Why: your history is yours, never a score of your work (docs/why.md#history-not-a-score)
struct History: View {
    @ObservedObject var model: GameModel
    let sessions: [Sitting] // oldest first
    @State var open = false
    @State private var picked: Double? // the start of the session whose summary shows

    var body: some View {
        let today = sessions.filter { Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.start)) }
        let before = sessions.filter { !Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.start)) }
        if !today.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Today").fontWeight(.medium).foregroundStyle(.secondary)
                // Three rows, then it scrolls; more room while one of them shows its summary.
                Capped(cap: today.contains { $0.start == picked } ? 360 : 3 * 26 + 2 * 8 + 6) {
                    ForEach(today.reversed(), id: \.start) { row($0) }
                }
            }
        }
        if !before.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(MenuPanel.expand) { open.toggle() } } label: {
                    HStack {
                        Text("Previously").fontWeight(.medium).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .modifier(Lit())
                }
                .buttonStyle(.plain)
                if open {
                    // ponytail: every session in the log, built at once; page it once that's slow
                    Capped(cap: 240) {
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

    /// A session as a row, like a network in Wi-Fi: the fuse in a pill, as big as in the menu bar, how many prompts, and when: how long ago, today, else the
    /// time it started. How it went waits in its summary.
    @ViewBuilder private func row(_ s: Sitting) -> some View {
        let today = Calendar.current.isDateInToday(Date(timeIntervalSince1970: s.start))
        Button { withAnimation(MenuPanel.expand) { picked = picked == s.start ? nil : s.start } } label: {
            HStack(spacing: 9) {
                FuseIcon().frame(width: FuseScene.fuseWidth, height: 22) // as big as in the menu bar, so in a pill
                    .padding(.horizontal, 5).frame(height: 26).background(Color.primary.opacity(0.08), in: Capsule())
                Text(s.prompts == 1 ? "1 prompt" : "\(s.prompts) prompts")
                Spacer(minLength: 0)
                Text(today ? ago(s.end, now: Date().timeIntervalSince1970) : clock(s.start)).monospacedDigit().foregroundStyle(.secondary)
            }
            .modifier(Lit())
        }
        .buttonStyle(.plain)
        .help(Game.sessionLine(s))
        if picked == s.start {
            SummaryCard(model: model, sitting: s)
                .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A list as tall as it is, up to `cap`, then it scrolls, with no scroller and soft ends, growing and shrinking with the panel. It reaches a little
/// past the sides, so the rows' light fits.
private struct Capped<Content: View>: View {
    let cap: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                    withAnimation(height == 0 ? nil : MenuPanel.expand) { height = new } // the first measure lands at once
                }
        }
        .scrollIndicators(.never)
        .modifier(EdgeFade())
        .frame(height: min(height, cap))
        .padding(.horizontal, -7)
    }
}
