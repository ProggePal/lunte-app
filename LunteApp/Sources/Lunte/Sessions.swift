import LunteCore
import SwiftUI

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

    /// The hottest heat in each of `slivers` equal slices of time, 0 where nothing was sent. All at once: one flat line.
    static func heats(_ events: [Event], now: Double = Date().timeIntervalSince1970) -> [Double] {
        guard let first = events.first?.ts, let last = events.last?.ts else { return [] }
        guard last > first else { return Array(repeating: events.map { $0.heat(at: now) }.max() ?? 0, count: 2) }
        var heats = Array(repeating: 0.0, count: slivers)
        for e in events {
            let i = min(slivers - 1, Int((e.ts - first) / (last - first) * Double(slivers)))
            heats[i] = max(heats[i], e.heat(at: now))
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
