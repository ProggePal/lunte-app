// The fuse game (contract §4): a pure replay of the whole log.
// Every message has heat and cool. Heat burns heat² of the fuse and cool mends some of it back, so calm messages
// barely touch it, and a burn cools off after 30 minutes. Too much heat at once and it blows: once per Sitting, and
// more heat after that escalates the same Boom.
import Foundation

public enum Game {
    public static let minFuse = 1.0
    public static let boomGrowth = 0.5          // a Boom lengthens the next stick; a calm Sitting shortens it again
    public static let sittingGap: Double = 1800 // a Sitting closes after 30 minutes without a prompt
    public static let cooling: Double = 1800    // a burn counts for 30 minutes
    public static let coolMend = 0.5            // a cool prompt mends coolMend × cool² of what's burning
    public static let maxTier = 3               // Boom, Chain reaction, Meltdown
    public static let closeCallLeft = 1.0 / 3   // a close call dips into the last third of the stick
    public static let coolPrompt = 1.0 / 3      // a prompt counts as cool from here: your AI's 1 of 3
    public static let ratingWait: Double = 90   // how long a rated message waits for the model before the word list decides
    static let spark = 0.01                     // heat² or cool² below this does nothing: a neutral message

    /// The Boom tiers, by `Boom.tier`.
    public static let tiers: [(emoji: String, name: String)] = [("💥", "Boom"), ("💥💥", "Chain reaction"), ("☢️", "Meltdown")]

    /// What one message does to the burn: heat², less `coolMend` × cool². Either below 0.01 counts as 0.
    public static func burn(_ e: Event, at now: Double) -> Double {
        let heat = pow(e.heat(at: now), 2), cool = pow(e.cool ?? 0, 2)
        return (heat >= spark ? heat : 0) - (cool >= spark ? coolMend * cool : 0)
    }

    public static func replay(_ events: [Event], now: Double) -> GameState {
        var s = GameState(fuse: minFuse, burned: 0, boomed: false, sittingOpen: false, currentBurns: [], booms: [])
        var sitting: Sitting?       // the one being replayed
        var burning: [Event] = []   // what burns or mends, from the last 30 minutes, since the Boom or its last tier
        var stick = minFuse         // the stick that blew: each tier fills it again
        var dip: Double?            // when the stick got into its last third

        // Each message in turn adds its burn, never below 0, so cool can't be banked before the heat. A dip into the
        // last third that climbs back out without a Boom is a close call.
        func settle(at t: Double) {
            s.burned = burning.reduce(0) { max(0, $0 + burn($1, at: now)) }
            guard !s.boomed else { return }
            if s.left <= closeCallLeft {
                dip = dip ?? t
            } else if let d = dip {
                sitting?.closeCalls.append(CloseCall(ts: d, cooled: t))
                dip = nil
            }
        }
        // Burns older than 30 minutes cool off, each when its 30 minutes are up.
        func expire(to t: Double) {
            while let first = burning.first, t - first.ts >= cooling {
                burning.removeFirst()
                settle(at: first.ts + cooling)
            }
            s.currentBurns.removeAll { t - $0.ts >= cooling }
        }
        // A Sitting ends: shorten the fuse unless it Boomed, and lay out a fresh stick.
        func close() {
            guard var done = sitting else { return }
            if done.boom == nil { s.fuse = max(minFuse, s.fuse - boomGrowth) }
            done.isOpen = false
            s.sittings.append(done)
            sitting = nil
            burning = []
            dip = nil
            s.burned = 0
            s.boomed = false
            s.currentBurns = []
            s.sittingStart = nil
        }

        for e in events.sorted(by: { $0.ts < $1.ts }) where e.burn != .heat {
            if e.burn == .rest { close(); continue } // a hurried break ended: the next prompt starts a fresh Sitting
            if let open = sitting, e.ts - open.end >= sittingGap {
                expire(to: open.end + sittingGap)
                close()
            }
            if sitting == nil {
                sitting = Sitting(start: e.ts, end: e.ts)
                s.sittingStart = e.ts
            }
            sitting!.end = e.ts
            sitting!.prompts += 1
            expire(to: e.ts)
            guard e.burn != .test else { continue }
            let heat = e.heat(at: now)
            sitting!.peakHeat = max(sitting!.peakHeat, heat)
            if (e.cool ?? 0) >= coolPrompt { sitting!.coolPrompts += 1 }
            if heat * heat >= spark {
                s.currentBurns.append(e)
                sitting!.lastBurn = e.ts
            }
            guard burn(e, at: now) != 0 else { continue }
            burning.append(e)
            settle(at: e.ts)
            if !s.boomed, s.burned >= s.fuse {
                stick = s.fuse
                s.boomed = true
                s.fuse += boomGrowth
                sitting!.boom = Boom(id: String(Int(e.ts * 1000)), ts: e.ts, litBy: s.currentBurns)
                s.booms.append(sitting!.boom!)
            } else if s.boomed, sitting!.tier < maxTier, s.burned >= stick {
                sitting!.boom!.escalations.append(e.ts)
                s.booms[s.booms.count - 1] = sitting!.boom!
            } else {
                continue
            }
            burning = [] // the burn starts again from zero, toward the next tier
            s.burned = 0
            dip = nil
        }

        if let open = sitting, now - open.end < sittingGap {
            s.sittingOpen = true
            expire(to: now)
            if s.boomed { s.freshAt = open.end + sittingGap }
            sitting!.isOpen = true
            s.sittings.append(sitting!)
        } else if let open = sitting {
            expire(to: open.end + sittingGap)
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
