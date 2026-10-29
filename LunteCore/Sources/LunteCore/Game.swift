// The fuse game (contract §4): a pure replay of the whole log.
// Every message has heat and cool. Heat burns heat² of the fuse and cool mends some of it back, so calm messages
// barely touch it, and a burn cools off after 30 minutes. Too much heat at once and it blows: once per Sitting, and
// more heat soon after escalates the same Boom.
import Foundation

public enum Game {
    // Why: habituation, so Booms stay rare (docs/why.md#rare-booms)
    public static let minFuse = 1.0
    public static let boomGrowth = 0.75         // a Boom lengthens the next stick
    public static let calmWorkdayShrink = 0.25  // a local day with prompts and no Boom shortens it again, at midnight
    public static let sittingGap: Double = 1800 // a Sitting closes after 30 minutes without a prompt
    public static let cooling: Double = 1800    // a burn counts for 30 minutes
    // Why: humour as reappraisal (docs/why.md#cool-mends)
    public static let coolMend = 0.5            // a cool prompt mends coolMend × cool² of what's burning
    // Why: a head start and room to grow, so a session has something to be proud of (docs/why.md#cool-grows)
    public static let full = 1.25               // cool grows a Sitting's stick up to a quarter past whole
    public static let growRate = 0.5            // the share of a cool prompt's spare mend that grows it
    // Why: venting feeds anger; tiers are for the same outburst, so most Booms stay plain (docs/why.md#tiers-flavour-not-volume)
    public static let maxTier = 3               // Boom, Chain reaction, Meltdown
    public static let escalationStep = 0.5      // each further half of the stick that blew is one tier up
    public static let escalationWindow: Double = 1800 // only within 30 minutes of the Boom; after that it stays blown
    // Why: competence, and relief right after the act (docs/why.md#close-call)
    public static let closeCallLeft = 1.0 / 3   // a close call dips into the last third of the stick
    static let epsilon = 1e-9                   // float slack: a heat-1 burn on a 1.5 stick leaves 0.33333333333333337
    public static let coolPrompt = 1.0 / 3      // a prompt counts as cool from here: your AI's 1 of 3
    public static let ratingWait: Double = 90   // how long a rated message waits for the model before the word list decides
    static let spark = 0.01                     // heat² or cool² below this does nothing: a neutral message
    public static let slowBurn: Double = 600    // a Boom whose burns built up over 10 minutes or more is a slow burn

    // Aura, one award per Sitting, the best thing that happened: the Club's points from Lunte's side (GAME.md).
    // Why: overjustification; aura never tracks how much you work (docs/why.md#aura-not-work)
    public static let coolSittingPrompts = 5    // a cool Sitting has this many prompts or more, and no Boom
    public static let coolSittingAura = 1       // at most once per local day
    public static let closeCallAura = 3         // any close call, even one a Boom came after
    // Why: the rewards come from people (docs/why.md#feedback-not-reward)
    public static let roastAura = 8             // decided by the Club's reactions, in the app and relay; it replaces the rest

    // The fuse lately: one number, 0–100, for how your fuse has run over days, shown in the popover's footer.
    // Why: tracking helps when it's about what you did, survives a bad day and never costs a rest (docs/why.md#fuse-lately)
    public static let latelyRest = 85.0         // where it starts, and where a rest brings it back up to
    public static let latelyPull = 0.02         // each prompt pulls it this share of the way toward where the fuse is
    public static let latelySittingDrop = 15.0  // one Sitting can take this much of it at most
    public static let restGap: Double = 4 * 3600 // this long without a prompt is a rest
    public static let restMend = 2.0 / 3        // a rest brings it this share of the way back up; it never lowers it

    // Why: venting feeds anger, so tiers escalate in flavour, not volume (docs/why.md#tiers-flavour-not-volume)
    /// The Boom tiers, by `Boom.tier`.
    public static let tiers: [(emoji: String, name: String)] = [("💥", "Boom"), ("💥💥", "Chain reaction"), ("☢️", "Meltdown")]

    /// What one message does to the burn: heat², less `mend`. Heat² below 0.01 counts as 0.
    public static func burn(_ e: Event, at now: Double) -> Double {
        let heat = pow(e.heat(at: now), 2)
        return (heat >= spark ? heat : 0) - mend(e)
    }

    /// What one message's cool mends: `coolMend` × cool², or 0 when cool² is below 0.01.
    public static func mend(_ e: Event) -> Double {
        let cool = pow(e.cool ?? 0, 2)
        return cool >= spark ? coolMend * cool : 0
    }

    /// Where the fuse is, on the scale of `GameState.lately`: a fresh stick is `latelyRest`, a full one 100, a blown one 0.
    static func latelyTarget(_ left: Double) -> Double {
        left <= 1 ? latelyRest * left : latelyRest + (100 - latelyRest) * (min(left, full) - 1) / (full - 1)
    }

    /// `timeZone` sets where the local days that shorten the fuse begin and end.
    public static func replay(_ events: [Event], now: Double, timeZone: TimeZone = .current) -> GameState {
        var s = GameState(fuse: minFuse, burned: 0, boomed: false, sittingOpen: false, currentBurns: [], booms: [])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var thermostat = minFuse    // the next stick; the open Sitting keeps the one it was given
        var today: Range<Double>?   // the local day of the last prompt
        var boomedToday = false
        var coolDay: Date?          // the local day whose cool Sitting has had its point
        var sitting: Sitting?       // the one being replayed
        var burning: [Event] = []   // what burns or mends, from the last 30 minutes, and since the Boom
        var stick = minFuse         // the stick that blew: each further half of it is a tier
        var dip: Double?            // when the stick got into its last third
        var lastScored: Double?     // the last prompt that moved the fuse lately
        var latelyStart: Double?    // the fuse lately when the open Sitting began

        // Each message in turn adds its burn, never below 0, so cool can't be banked against heat to come: what it has
        // spare grows the stick instead. A dip into the last third that climbs back out without a Boom is a close call.
        func settle(at t: Double) {
            s.burned = burning.reduce(0) { max(0, $0 + burn($1, at: now)) }
            guard !s.boomed else { return }
            if inLastThird(s.left) {
                dip = dip ?? t
            } else if let d = dip {
                sitting?.closeCalls.append(CloseCall(ts: d, cooled: t))
                sitting?.aura = closeCallAura
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
        // A local day with prompts and no Boom is a calm workday: once it's over, the next stick is shorter.
        // Why: habituation, so Booms stay rare (docs/why.md#rare-booms)
        func dayEnds(by t: Double) {
            guard let day = today, t >= day.upperBound else { return }
            if !boomedToday { thermostat = max(minFuse, thermostat - calmWorkdayShrink) }
            today = nil
            boomedToday = false
        }
        // A Sitting ends: lay out a fresh stick.
        // Why: a fresh start per session, and only at its close (docs/why.md#fresh-start)
        func close() {
            guard var done = sitting else { return }
            // Why: overjustification; a cool Sitting counts once a day, however long you work (docs/why.md#aura-not-work)
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: done.start))
            if done.closeCalls.isEmpty, done.boom == nil, done.prompts >= coolSittingPrompts, day != coolDay {
                done.aura = coolSittingAura
                coolDay = day
            }
            s.fuse = thermostat
            done.isOpen = false
            s.sittings.append(done)
            sitting = nil
            burning = []
            dip = nil
            s.burned = 0
            s.grown = 0
            s.boomed = false
            s.currentBurns = []
            s.sittingStart = nil
            latelyStart = nil
        }
        // A rest of `restGap` or more: the fuse lately comes most of the way back up.
        // Why: a bad day mostly heals, and a rest never costs you (docs/why.md#fuse-lately)
        func rested() {
            if s.lately < latelyRest { s.lately += (latelyRest - s.lately) * restMend }
            s.latelyDayStart = s.lately // and a new day starts
        }

        for e in events.sorted(by: { $0.ts < $1.ts }) where e.burn != .heat {
            if e.burn == .rest { close(); continue } // a hurried break ended: the next prompt starts a fresh Sitting
            if let open = sitting, e.ts - open.end >= sittingGap {
                expire(to: open.end + sittingGap)
                close()
            }
            dayEnds(by: e.ts)
            if sitting == nil {
                sitting = Sitting(start: e.ts, end: e.ts, fuse: thermostat)
                s.sittingStart = e.ts
                s.fuse = thermostat
            }
            sitting!.end = e.ts
            sitting!.prompts += 1
            expire(to: e.ts)
            guard e.burn != .test else { continue }
            if let last = lastScored, e.ts - last >= restGap { rested() }
            // Every prompt pulls the fuse lately a little toward where the fuse is once it's landed, by its share
            // rather than its count, so it never tracks how much you work; one Sitting can only take so much.
            // Why: feedback about what you did, that survives a bad day (docs/why.md#fuse-lately)
            defer {
                let start = latelyStart ?? s.lately
                latelyStart = start
                s.lately = max(start - latelySittingDrop, s.lately + latelyPull * (latelyTarget(s.left) - s.lately))
                sitting!.lately = s.lately - start
                lastScored = e.ts
            }
            if today == nil {
                let start = calendar.startOfDay(for: Date(timeIntervalSince1970: e.ts))
                today = start.timeIntervalSince1970..<calendar.date(byAdding: .day, value: 1, to: start)!.timeIntervalSince1970
            }
            let heat = e.heat(at: now)
            sitting!.peakHeat = max(sitting!.peakHeat, heat)
            if (e.cool ?? 0) >= coolPrompt { sitting!.coolPrompts += 1 }
            if heat * heat >= spark {
                s.currentBurns.append(e)
                sitting!.lastBurn = e.ts
            }
            guard burn(e, at: now) != 0 else { continue }
            // Why: cool with nothing left to mend grows this Sitting's stick, up to full, until it closes; burns heal,
            // growth stays, so there's nothing to keep alive (docs/why.md#cool-grows)
            let spare = -(s.burned + burn(e, at: now))
            if spare > 0, !s.boomed {
                s.grown = min(full - 1, s.grown + growRate * spare / s.fuse)
                sitting!.grew = max(sitting!.grew, s.grown)
            }
            burning.append(e)
            settle(at: e.ts)
            // Why: venting feeds anger, so more heat escalates the one Boom (docs/why.md#one-boom-per-session)
            if !s.boomed, s.burned >= s.fuse * (1 + s.grown) {
                stick = s.fuse
                s.boomed = true
                boomedToday = true
                thermostat += boomGrowth
                s.fuse = thermostat
                sitting!.boom = Boom(id: String(Int(e.ts * 1000)), ts: e.ts, litBy: s.currentBurns)
                s.booms.append(sitting!.boom!)
                burning = [] // the burn starts again from zero, toward the tiers
                s.burned = 0
                s.grown = 0
                dip = nil
            } else if s.boomed, var boom = sitting!.boom, e.ts - boom.ts < escalationWindow {
                // Why: tiers in flavour, and only for the same outburst (docs/why.md#tiers-flavour-not-volume)
                let tier = min(maxTier, 1 + Int((s.burned + epsilon) / (escalationStep * stick)))
                guard tier > boom.tier else { continue }
                boom.escalations += Array(repeating: e.ts, count: tier - boom.tier) // one prompt can step up two
                sitting!.boom = boom
                s.booms[s.booms.count - 1] = boom
            }
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
        dayEnds(by: now)
        if !s.sittingOpen || s.boomed { s.fuse = thermostat }
        if let last = lastScored, now - last >= restGap { rested() } // the morning shows the rest before its first prompt
        return s
    }

    // Why: never fake a near-miss; the line dips exactly as far as the fuse did (docs/why.md#never-fake-reactions)
    /// The fuse across a Sitting, as steps: what's left at its start, after each prompt that burns, mends or grows it,
    /// and as each burn cools off, up to its close, when it's fresh again. Past 1 is what cool grew, up to `full`. 0 from
    /// the Boom on. `events` are the Sitting's.
    public static func fuseLine(_ s: Sitting, _ events: [Event], now: Double) -> [(ts: Double, left: Double)] {
        let close = s.end + sittingGap
        let burns = events.filter { ![.heat, .test, .rest].contains($0.burn) && burn($0, at: now) != 0 }.sorted { $0.ts < $1.ts }
        let times = Set([s.start, close] + burns.flatMap { [$0.ts, $0.ts + cooling] }).filter { $0 <= close }.sorted()
        // What's burning at `t` from the first `n` prompts, each added in turn, never below 0.
        let burning = { (t: Double, n: Int) in burns[..<n].filter { t - $0.ts < cooling }.reduce(0) { max(0, $0 + burn($1, at: now)) } }
        var grown = 0.0, landed = 0 // as the replay: a prompt's mend past what's still burning grows it, up to full
        return times.map { t in
            if let boom = s.boom, t >= boom.ts, t < close { return (t, 0) }
            if t == close { return (t, 1) } // a fresh fuse
            while landed < burns.count, burns[landed].ts <= t { // one at a time, even when two share a time
                let spare = -(burning(burns[landed].ts, landed) + burn(burns[landed], at: now))
                if spare > 0 { grown = min(full - 1, grown + growRate * spare / s.fuse) }
                landed += 1
            }
            return (t, max(0, 1 + grown - burning(t, landed) / s.fuse))
        }
    }

    /// The unblown fuse in a word, from what it did, never a guess at your mood: "Last third"; "Cooling off" once no
    /// new heat has come for 5 minutes; "Slow burn" once it's been burning for `slowBurn`; "Burning"; else "Cool".
    /// After a Boom, the menu bar's words take over.
    public static func word(_ s: GameState, now: Double) -> String {
        guard s.left < 1, let first = s.currentBurns.first, let last = s.currentBurns.last else { return "Cool" }
        if inLastThird(s.left) { return "Last third" }
        if now - last.ts >= 300 { return "Cooling off" } // ponytail: 5 minutes by feel, not tuned on a replay
        return now - first.ts >= slowBurn ? "Slow burn" : "Burning"
    }

    // Why: competence; a close call is never missed by a rounding error (docs/why.md#close-call)
    /// In the stick's last third: `closeCallLeft` or less left, give or take float rounding.
    public static func inLastThird(_ left: Double) -> Bool { left <= closeCallLeft + epsilon }

    public static func stickText(_ state: GameState) -> String {
        if state.boomed { return "💥" }
        return "🧨" + (inLastThird(state.left) ? "✨" : String(repeating: "━", count: Int((state.left * 3).rounded(.up))))
    }

    /// The fuse lately's steps, from the top, each from its lowest score: how in sync you and your agent have been. A
    /// rest brings you back to In sync.
    public static let latelySteps: [(from: Int, word: String)] = [
        (95, "Locked in"), (85, "In sync"), (70, "Steady"), (55, "Drifting"), (40, "Swinging"), (20, "Rough"), (0, "Short fuse"),
    ]
    /// Which of `latelySteps` a score is on, 0 at the top.
    public static func latelyStep(_ score: Int) -> Int { latelySteps.firstIndex { score >= $0.from } ?? latelySteps.count - 1 }
    public static func latelyWord(_ score: Int) -> String { latelySteps[latelyStep(score)].word }

    /// cool, mild, warm, hot, boiling.
    public static func heatWord(_ heat: Double) -> String {
        heat < 0.15 ? "cool" : heat < 0.35 ? "mild" : heat < 0.6 ? "warm" : heat < 0.85 ? "hot" : "boiling"
    }

    // Why: the peak-end rule (docs/why.md#peak-end)
    /// One line about a Sitting, built from what happened, never a guess at your mood. It ends on the recovery when
    /// there is one, since that's what you remember:
    /// - "Cool all the way. 42 prompts.", or "Grew to 118 %. 42 prompts." or "Grew to full. 42 prompts." when cool grew it
    /// - "Close call at 14:12. Cooled off." or "3 close calls, the last at 15:03. Cooled off."
    /// - "Slow burn. Boomed at 14:12. Cooled off by 14:40." ("Slow burn." after `slowBurn`, "Cooled off by" with `cooledOff`)
    /// - "Chain reaction at 15:03." or "Meltdown at 15:20.", the top tier, with the same recovery
    public static func sessionLine(_ s: Sitting, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func at(_ t: Double) -> String {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        let recovery = s.cooledOff.map { " Cooled off by \(at($0))." } ?? ""
        if let boom = s.boom, let top = boom.escalations.last {
            return "\(tiers[boom.tier - 1].name) at \(at(top))." + recovery
        }
        if let boom = s.boom {
            let slow = boom.ts - (boom.litBy.first?.ts ?? boom.ts) >= slowBurn
            return (slow ? "Slow burn. " : "") + "Boomed at \(at(boom.ts))." + recovery
        }
        if let last = s.closeCalls.last {
            let n = s.closeCalls.count
            return (n == 1 ? "Close call at \(at(last.ts))." : "\(n) close calls, the last at \(at(last.ts)).") + " Cooled off."
        }
        // Why: a session has something to be proud of (docs/why.md#cool-grows)
        let grew = s.grew >= full - 1 - epsilon ? "Grew to full. " : s.grew > 0.005 ? "Grew to \(Int(((1 + s.grew) * 100).rounded(.down))) %. " : "Cool all the way. "
        return grew + "\(s.prompts) prompt" + (s.prompts == 1 ? "." : "s.")
    }

    // Why: overjustification; aura never tracks how much you work (docs/why.md#aura-not-work)
    /// A Sitting's aura, without roasts: its one award, the best thing that happened, as the replay worked it out
    /// (`Sitting.aura`). `closeCallAura` with any close call; else `coolSittingAura` once a Sitting of
    /// `coolSittingPrompts` or more closes without a Boom, for the first one that day; else 0. An open Sitting's cool
    /// point waits for the close, so the aura it shows never goes down.
    public static func aura(_ s: Sitting) -> Int { s.aura }
}
