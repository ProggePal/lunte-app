import LunteCore
import SwiftUI

/// A closed session at a glance: how long it ran, its heat line, its one line, then its aura, so it ends on the
/// recovery and what it earned.
// Why: the peak-end rule; a session is remembered by its peak and its end (docs/why.md#summary-next-open)
struct SummaryCard: View {
    var title: String?
    let sitting: Sitting
    let events: [Event]
    let club: String?

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
            if aura > 0 { Text("+\(aura) aura" + (club.map { " for \($0)" } ?? "")).font(.callout.weight(.medium)) }
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
