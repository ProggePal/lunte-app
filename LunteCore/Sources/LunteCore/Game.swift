// The fuse game (contract §4): a pure replay of the whole log.
import Foundation

public enum Game {
    public static let minFuse = 2
    public static let sittingGap: Double = 600 // a 10-minute break gives a fresh stick

    public static func replay(_ events: [Event], now: Double) -> GameState {
        var s = GameState(fuse: minFuse, pieces: minFuse, boomed: false, sittingOpen: false, currentBurns: [], booms: [])
        var last: Double?

        // A Sitting ends: shorten the fuse unless it Boomed, and lay out a fresh stick.
        func close() {
            if !s.boomed { s.fuse = max(minFuse, s.fuse - 1) }
            s.pieces = s.fuse
            s.boomed = false
            s.currentBurns = []
        }

        for e in events.sorted(by: { $0.ts < $1.ts }) {
            if let last, e.ts - last >= sittingGap { close() }
            last = e.ts
            guard e.burn == .tell || e.burn == .lose else { continue } // .none and .test only keep a Sitting open
            s.currentBurns.append(e) // keeps Burns after a Boom too; litBy is the snapshot up to the Boom
            if s.boomed { continue }
            let cost = e.burn == .lose ? 2 : 1 // telling it off burns one piece, losing it burns two
            if e.burn == .lose && s.pieces <= cost {
                s.pieces = 0
                s.boomed = true
                s.fuse += 1
                s.booms.append(Boom(id: String(Int(e.ts * 1000)), ts: e.ts, litBy: s.currentBurns))
            } else {
                s.pieces = max(1, s.pieces - cost) // .tell never takes the last piece: it stays on the spark
            }
        }

        if let last, now - last < sittingGap {
            s.sittingOpen = true
        } else if last != nil {
            close()
        }
        return s
    }

    public static func stickText(_ state: GameState) -> String {
        if state.boomed { return "💥" }
        return "🧨" + (state.pieces == 1 ? "✨" : String(repeating: "━", count: state.pieces))
    }

    /// "10:12 told off · 14:40 lost it", in local time.
    public static func litByText(_ boom: Boom) -> String {
        boom.litBy.map { e in
            let t = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: e.ts))
            return String(format: "%02d:%02d ", t.hour ?? 0, t.minute ?? 0) + (e.burn == .lose ? "lost it" : "told off")
        }.joined(separator: " · ")
    }
}
