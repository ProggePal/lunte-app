// A finished session, told as a story (contract §4): a name for what you did and how it went, a line for its shape, when
// you were cool, and what its aura was for. Built from facts only, so it's always true, and never about what you did
// wrong: the aura does the scoring. Your AI adds personal names at fuse setup (§8); stock names cover everyone else.
import Foundation

// Why: identity and a laugh, never a verdict (docs/why.md#session-names)
public enum Story {
    /// How a session went, from what the fuse did.
    public enum Energy: String, CaseIterable, Sendable {
        /// It barely moved.
        case steady
        /// Cool grew it, or the cool kept coming.
        case buzzing
        /// It burned through half or more, or got into the last third.
        case intense
        /// It blew.
        case boom
    }

    /// A session as its fuse saw it: the lowest it got, the highest (past 1 is what cool grew), and where it was at the
    /// last prompt. `line` is the session's fuse as steps (`Game.fuseLine`).
    static func shape(_ s: Sitting, _ line: [(ts: Double, left: Double)]) -> (low: Double, peak: Double, end: Double) {
        let lefts = [1.0] + line.map(\.left)
        return (lefts.min() ?? 1, lefts.max() ?? 1, line.last { $0.ts <= s.end }?.left ?? 1)
    }

    public static func energy(_ s: Sitting, _ line: [(ts: Double, left: Double)]) -> Energy {
        let (low, peak, _) = shape(s, line)
        if s.boom != nil { return .boom }
        if !s.closeCalls.isEmpty || low <= 0.5 { return .intense }
        return peak >= 1.1 || s.coolPrompts >= 3 ? .buzzing : .steady
    }

    /// What it was about: Laya's topic for at least 3 prompts and 40 % of those with one, ignoring "other"
    /// (`Vibe.topic`); else when it started: "early" before 8 on a weekday, "late" from 22 to 5, "weekend", or "day".
    public static func activity(_ s: Sitting, _ events: [Event], calendar: Calendar = .current) -> String {
        if let topic = Vibe.topic(events) { return topic }
        let start = Date(timeIntervalSince1970: s.start), hour = calendar.component(.hour, from: start)
        if hour >= 22 || hour < 5 { return "late" }
        if calendar.isDateInWeekend(start) { return "weekend" }
        return hour < 8 ? "early" : "day"
    }

    /// The session's shape in one kind line, from the facts: "Up, down, and up again." Sessions with the same shape
    /// take turns with the wordings, by when they started.
    public static func arc(_ s: Sitting, _ line: [(ts: Double, left: Double)]) -> String {
        let (low, peak, end) = shape(s, line), grew = peak >= 1.1
        let pick = { (lines: [String]) in lines[Int(s.start / 1800) % lines.count] }
        if let boom = s.boom {
            if grew { return pick(["Flew a little close to the sun.", "Up, up, and away."]) }
            let slow = boom.ts - (boom.litBy.first?.ts ?? boom.ts) >= Game.slowBurn
            return slow ? pick(["Built up to a big finish.", "A long fuse, then a bang."]) : pick(["Went out with a bang.", "Short and loud."])
        }
        if !s.closeCalls.isEmpty { return pick(["Down to the wire, then back.", "Close, but not quite."]) }
        if grew { return low >= 0.85 ? pick(["Better and better.", "Only up from here."]) : "Up, down, and up again." }
        // 85 %: where the bars turn orange, so the words never call a burned session smooth.
        if low < 0.85 { return end >= 0.9 ? pick(["A wobble, then a strong finish.", "Bumps, then smooth."]) : "A bumpy ride." }
        return pick(["Steady all the way.", "Smooth from start to finish.", "Not a bump in sight."])
    }

    /// What its aura was for, said plainly, or nil with none.
    public static func auraLine(_ s: Sitting) -> String? {
        if s.aura == Game.closeCallAura { return "+\(s.aura) aura for holding it together" }
        if s.aura == Game.coolSittingAura { return "+\(s.aura) aura for a cool session, your first today" }
        return nil
    }

    /// When you were cool: each cool prompt for as long as its mend counts (`Game.cooling`, 30 minutes), run together
    /// where they overlap.
    public static func coolStretches(_ events: [Event]) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        for t in events.filter({ $0.burn != .heat && ($0.cool ?? 0) >= Game.coolPrompt }).map(\.ts).sorted() {
            if let last = out.last, t <= last.upperBound { out[out.count - 1] = last.lowerBound...(t + Game.cooling) }
            else { out.append(t...(t + Game.cooling)) }
        }
        return out
    }

    /// A session to name: its facts, its prompts, and its fuse line.
    public typealias Told = (sitting: Sitting, events: [Event], line: [(ts: Double, left: Double)])

    /// A name for every session, in order (oldest first, as `GameState.sittings`). Facts pick the names that fit: the
    /// energy, and the activity for names that name one. Then taste picks among them: yours (from fuse setup) before
    /// stock, never one already used that day, and the one used longest ago, so names come round slowly. The same log
    /// always gives the same names.
    // ponytail: replayed from the first session every time; keep the names if history ever gets long enough to matter
    public static func names(_ sessions: [Told], personal: [Vibe] = [], calendar: Calendar = .current) -> [String] {
        var used: [String: Double] = [:], today: (day: Date, names: Set<String>)?
        return sessions.map { told in
            let (s, events, line) = told
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: s.start))
            if today?.day != day { today = (day, []) }
            let energy = Self.energy(s, line), activity = Self.activity(s, events, calendar: calendar)
            let short = s.prompts < 3 && s.boom == nil
            let yours = short ? [] : personal.filter { band($0.band) == energy && ($0.topic == nil || $0.topic == activity) }.map(\.label)
            let stock = short ? Self.short : (Self.stock[activity] ?? Self.stock["day"]!)[energy]!
            let fresh = { (names: [String]) in names.filter { !today!.names.contains($0) } }
            let pool = [fresh(yours), fresh(stock), stock].first { !$0.isEmpty }!
            let order = yours + stock // yours first, then the list's own order
            let name = pool.min { (used[$0] ?? 0, order.firstIndex(of: $0) ?? 0) < (used[$1] ?? 0, order.firstIndex(of: $1) ?? 0) }! // the longest ago
            used[name] = s.start
            today!.names.insert(name)
            return name
        }
    }

    /// The energy a personal name from fuse setup is for.
    static func band(_ band: Vibe.Band) -> Energy {
        switch band {
        case .calm: .steady
        case .cool: .buzzing
        case .warm, .hot: .intense
        case .explosive: .boom
        }
    }

    /// Under 3 prompts, unless it blew.
    static let short = ["Quick one", "In and out", "Just popping in", "A quick word", "Flying visit"]

    /// Stock names, by what you did and how it went. Plain words with a wink: about the work and the energy, never a
    /// feeling named or a verdict, and a Boom is a laugh, not a scolding. A kind of work comes from `Vibe.topics`; the
    /// rest go by the time of day.
    static let stock: [String: [Energy: [String]]] = [
        "code": [.steady: ["Heads-down coding", "Deep work", "Quiet commits", "Clean code hours"],
                 .buzzing: ["Code and banter", "In the groove", "Pair programming pals", "Happy hacking"],
                 .intense: ["Bug hunt", "Stack trace safari", "Refactor rally", "Debugging deep dive"],
                 .boom: ["Bug bash showdown", "Works on my machine", "Segfault saga", "Merge conflict meltdown"]],
        "design": [.steady: ["Pixel polishing", "Nudging pixels", "Design hour", "Quiet craft"],
                   .buzzing: ["Design jam", "Looking sharp", "Pixel party", "Moodboard magic"],
                   .intense: ["Pixel pushing", "Kerning crisis", "Just one more tweak", "Alignment quest"],
                   .boom: ["Back to the drawing board", "Design by fire", "Pixel meltdown", "Redesign rodeo"]],
        "writing": [.steady: ["Words flowing", "Drafting away", "Writing room", "Page by page"],
                    .buzzing: ["Wordsmith hour", "On a roll", "Copy jam", "Fresh ink"],
                    .intense: ["Copy crunch", "Word wrestling", "Rewrite rally", "Deadline drafting"],
                    .boom: ["Rewrite rodeo", "Red pen rampage", "Draft zero", "Blank page bonanza"]],
        "business": [.steady: ["Business plan hours", "Planning mode", "Spreadsheet serenity", "Inbox zero-ish"],
                     .buzzing: ["Founder mode", "Deal-making mood", "Pitch perfect", "Big plans"],
                     .intense: ["Numbers crunch", "Pricing puzzle", "Pitch pressure", "Quarter-end push"],
                     .boom: ["Board meeting energy", "Hostile takeover", "Bull run", "Pivot or perish"]],
        "voice": [.steady: ["Talking it through", "Voice notes", "Audio hour", "Thinking aloud"],
                  .buzzing: ["Voice lab vibes", "Sound check", "Mic check", "Good listener"],
                  .intense: ["Can you hear me now", "Testing, testing", "Feedback loop", "Say that again"],
                  .boom: ["Mic drop", "Loud and clear", "Unmuted", "Turn it up to eleven"]],
        "shipping": [.steady: ["Smooth shipping", "Release mode", "Shipping season", "Steady deploys"],
                     .buzzing: ["Victory lap", "Green across the board", "Ship it, ship it", "Launch day glow"],
                     .intense: ["Mad push to prod", "Merge to prod now", "Deadline sprint", "Release crunch"],
                     .boom: ["Hotfix hero", "Friday deploy energy", "Ship happens", "Rollback rodeo"]],
        "ideas": [.steady: ["Thinking out loud", "Whiteboard hours", "Idea garden", "Daydream drafts"],
                  .buzzing: ["Big idea energy", "Galaxy brain", "Idea avalanche", "Brainwave"],
                  .intense: ["Brainstorm firestorm", "Ten tabs of ideas", "Pivot party", "Idea pressure cooker"],
                  .boom: ["Mind blown", "Brain overflow", "Idea explosion", "Eureka, loudly"]],
        "early": [.steady: ["Early bird", "First light", "Before the coffee"],
                  .buzzing: ["Rise and shine", "Bright and early", "Morning glory"],
                  .intense: ["Coffee and chaos", "Straight in at the deep end", "Morning rush"],
                  .boom: ["Morning fireworks", "Wake-up call", "Breakfast bang"]],
        "late": [.steady: ["Night owl", "Burning the midnight oil", "After dark"],
                 .buzzing: ["After-hours club", "Night shift, good company", "Moonlight sessions"],
                 .intense: ["One more thing before bed", "Midnight push", "Small hours"],
                 .boom: ["Midnight fireworks", "Late-night bang", "Bang in the night"]],
        "weekend": [.steady: ["Weekend tinkering", "Side-project hours", "Pottering about"],
                    .buzzing: ["Weekend vibes", "Off the clock, on a roll", "Lazy day, good company"],
                    .intense: ["Weekend warrior", "No rest for the keen", "Weekend overtime"],
                    .boom: ["Weekend fireworks", "Weekend special", "Weekend wake-up call"]],
        "day": [.steady: ["Steady session", "Business as usual", "Plain sailing", "Nothing to report"],
                .buzzing: ["Good company", "Good vibes only", "In good spirits", "Best of friends"],
                .intense: ["Full throttle", "High gear", "Turbo mode", "Pedal to the metal"],
                .boom: ["Kaboom", "Big bang", "Fireworks", "That escalated"]],
    ]
}
