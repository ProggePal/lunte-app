// The fuse game (contract §4): a pure replay of the whole log.
// Every message has heat. It burns heat² of the fuse, so calm messages barely touch it, and a burn cools off after
// 30 minutes. Too much heat at once and it blows.
import Foundation

public enum Game {
    public static let minFuse = 1.0
    public static let boomGrowth = 0.5      // a Boom lengthens the next stick; a calm Sitting shortens it again
    public static let sittingGap: Double = 600  // a 10-minute break gives a fresh stick
    public static let cooling: Double = 1800    // a burn counts for 30 minutes
    public static let ratingWait: Double = 90   // how long a rated message waits for the model before the word list decides
    static let spark = 0.01                     // heat² below this doesn't burn: a calm message

    public static func replay(_ events: [Event], now: Double) -> GameState {
        var s = GameState(fuse: minFuse, burned: 0, boomed: false, sittingOpen: false, currentBurns: [], booms: [])
        var last: Double?
        var sittingBoomed = false

        // A Sitting ends: shorten the fuse unless it Boomed, and lay out a fresh stick.
        func close() {
            if !sittingBoomed { s.fuse = max(minFuse, s.fuse - boomGrowth) }
            s.burned = 0
            s.boomed = false
            s.currentBurns = []
            s.sittingStart = nil
            sittingBoomed = false
        }
        // Burns older than 30 minutes cool off; once the last one has, a 💥 is a fresh stick again.
        func cool(_ t: Double) {
            s.currentBurns.removeAll { t - $0.ts >= cooling }
            if s.currentBurns.isEmpty { s.boomed = false }
            s.burned = s.currentBurns.reduce(0) { $0 + pow($1.heat(at: now), 2) }
        }

        for e in events.sorted(by: { $0.ts < $1.ts }) where e.burn != .heat {
            if e.burn == .rest { // a hurried break ended: close now, and the next prompt starts a fresh Sitting
                if last != nil { close() }
                last = nil
                continue
            }
            if let last, e.ts - last >= sittingGap { close() }
            if s.sittingStart == nil { s.sittingStart = e.ts }
            last = e.ts
            cool(e.ts)
            guard e.burn != .test, pow(e.heat(at: now), 2) >= spark else { continue }
            s.currentBurns.append(e)
            cool(e.ts)
            if !s.boomed && s.burned >= s.fuse {
                s.boomed = true
                sittingBoomed = true
                s.fuse += boomGrowth
                s.booms.append(Boom(id: String(Int(e.ts * 1000)), ts: e.ts, litBy: s.currentBurns))
            }
        }

        if let last, now - last < sittingGap {
            s.sittingOpen = true
            cool(now)
            if s.boomed, let hot = s.currentBurns.last?.ts { s.freshAt = min(last + sittingGap, hot + cooling) }
        } else if last != nil {
            close()
        }
        return s
    }

    public static func stickText(_ state: GameState) -> String {
        if state.boomed { return "💥" }
        return "🧨" + (state.left <= 1.0 / 3 ? "✨" : String(repeating: "━", count: Int((state.left * 3).rounded(.up))))
    }

    /// cool, mild, warm, hot, boiling.
    public static func heatWord(_ heat: Double) -> String {
        heat < 0.15 ? "cool" : heat < 0.35 ? "mild" : heat < 0.6 ? "warm" : heat < 0.85 ? "hot" : "boiling"
    }
}
