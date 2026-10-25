import LunteCore
import SwiftUI

/// A closed session at a glance: how long it ran, its heat line, its one line, then its aura, so it ends on the
/// recovery and what it earned.
// Why: the peak-end rule; a session is remembered by its peak and its end (docs/why.md#summary-next-open)
struct SummaryCard: View {
    var title: String?
    let sitting: Sitting
    let events: [Event]

    var body: some View {
        let aura = Game.aura(sitting)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let title { Text(title).font(.headline) }
                Spacer()
                Text(length(sitting)).font(.caption).foregroundStyle(.secondary)
            }
            HeatLine(events: events).frame(height: 24)
            Text(Game.sessionLine(sitting)).font(.system(.callout, design: .serif)).fixedSize(horizontal: false, vertical: true)
            // ponytail: no Club named, since nothing sends aura there yet; that comes with Leagues
            if aura > 0 { Text("+\(aura) aura").font(.callout.weight(.medium)) }
        }
    }
}

/// How long a session ran, first message to last: "under a minute", "40 min", "2 h 5 min".
func length(_ s: Sitting) -> String {
    let m = Int((s.end - s.start) / 60)
    return m < 1 ? "under a minute" : m < 60 ? "\(m) min" : "\(m / 60) h" + (m % 60 > 0 ? " \(m % 60) min" : "")
}

/// A heat line: the hottest message in each sliver of time from the first message to the last. Grey low down, orange
/// and red up high, the same as the dots. Quiet stretches lie flat along the bottom.
struct HeatLine: View {
    let events: [Event]
    static let slivers = 48 // ponytail: a fixed count; across the popover that's one every 5 points

    var body: some View {
        LinearGradient(stops: [
            .init(color: Color.secondary.opacity(0.6), location: 0.34), .init(color: .orange, location: 0.38),
            .init(color: .orange, location: 0.8), .init(color: .red, location: 0.84),
        ], startPoint: .bottom, endPoint: .top)
            .mask(Trace(heats: Self.heats(events)).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)))
            .accessibilityHidden(true)
    }

    /// The hottest heat in each of `slivers` equal slices of time, from events sorted by time. Neutral messages
    /// (under 0.15, where nothing is "cooled off" either) and slices with nothing sent are 0. All at once: one flat line.
    static func heats(_ events: [Event], now: Double = Date().timeIntervalSince1970) -> [Double] {
        guard let first = events.first?.ts, let last = events.last?.ts else { return [] }
        let heat = { (e: Event) in e.heat(at: now) < 0.15 ? 0 : e.heat(at: now) }
        guard last > first else { return Array(repeating: events.map(heat).max() ?? 0, count: 2) }
        var heats = Array(repeating: 0.0, count: slivers)
        for e in events {
            let i = min(slivers - 1, Int((e.ts - first) / (last - first) * Double(slivers)))
            heats[i] = max(heats[i], heat(e))
        }
        return heats
    }
}

/// The heats, left to right, as one line: 0 at the bottom, 1 at the top.
private struct Trace: Shape {
    let heats: [Double]

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1), step = r.width / Double(max(heats.count - 1, 1))
        return Path { p in
            for (i, heat) in heats.enumerated() {
                let point = CGPoint(x: r.minX + step * Double(i), y: r.maxY - r.height * heat)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
    }
}

/// Your past sessions by day, newest first: "Today · 2 sessions · 4 aura", then each session's start and line. Click
/// one to see its summary again. It's read from the log on this Mac and never sent, and it never adds up how long you
/// worked.
// Why: your history is yours, never a score of your work (docs/why.md#history-not-a-score)
struct History: View {
    let sessions: [Sitting] // oldest first
    let events: (Sitting) -> [Event]
    @State private var open = false
    @State private var picked: Double? // the start of the session whose summary shows
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: { Label("History", systemImage: open ? "chevron.down" : "chevron.right") }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            if open {
                // ponytail: every session in the log, built at once; page it once that's slow
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(days, id: \.day) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(header(day.day, day.sessions)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(day.sessions, id: \.start) { row($0) }
                            }
                        }
                    }
                    .padding(.trailing, 8) // room for the scroller
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                }
                .frame(height: min(height, 240)) // as tall as the list, up to 240 points
            }
        }
    }

    /// Newest day first, and newest session first within it.
    private var days: [(day: Date, sessions: [Sitting])] {
        Dictionary(grouping: sessions.reversed()) { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: $0.start)) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    /// "Today · 2 sessions · 4 aura": how many sessions and what they earned, never how long they ran.
    private func header(_ day: Date, _ sessions: [Sitting]) -> String {
        let calendar = Calendar.current, aura = sessions.map(Game.aura).reduce(0, +)
        let name = calendar.isDateInToday(day) ? "Today" : calendar.isDateInYesterday(day) ? "Yesterday"
            : day.formatted(.dateTime.weekday(.wide).day().month())
        return ([name, sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"] + (aura > 0 ? ["\(aura) aura"] : []))
            .joined(separator: " · ")
    }

    @ViewBuilder private func row(_ s: Sitting) -> some View {
        let aura = Game.aura(s)
        Button { picked = picked == s.start ? nil : s.start } label: {
            HStack(spacing: 6) {
                Text(clock(s.start)).monospacedDigit().foregroundStyle(.secondary)
                Text(Game.sessionLine(s)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if aura > 0 { Text("+\(aura)").foregroundStyle(.secondary) }
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Game.sessionLine(s))
        if picked == s.start {
            SummaryCard(sitting: s, events: events(s))
                .padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
