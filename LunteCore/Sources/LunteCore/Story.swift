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

    /// A prompt that turned the session, and what it did to the fuse: a share of the stick, burnt (below 0) or brought
    /// back (above), or for the one that set it off, all that was left.
    public struct Move: Equatable, Sendable {
        public enum Kind: String, Sendable { case setItOff = "Set it off", burnt = "Burnt the most", back = "Brought it back" }
        public let kind: Kind
        public let event: Event
        public let change: Double
    }

    // Why: your own words at the turns are what you'll recall (docs/why.md#session-story)
    /// At most three prompts that turned the session, in the order they came: the one that set off its Boom, the one
    /// that burnt the most, and the one that brought it back the most, each only if it moved the fuse by `moveSize` or
    /// more. Picked by what the fuse did, so a steady session has none. `line` is its fuse line (`Game.fuseLine`).
    public static func moves(_ s: Sitting, _ events: [Event], _ line: [(ts: Double, left: Double)]) -> [Move] {
        let before = { (t: Double) in line.last { $0.ts < t }?.left ?? 1 }
        let turns = events.map { e in (e, (line.last { $0.ts <= e.ts }?.left ?? 1) - before(e.ts)) }.filter { $0.0.ts != s.boom?.ts }
        var moves: [Move] = []
        if let boom = s.boom, let e = events.first(where: { $0.ts == boom.ts }) { moves.append(Move(kind: .setItOff, event: e, change: -before(e.ts))) }
        if let (e, change) = turns.min(by: { $0.1 < $1.1 }), change <= -moveSize { moves.append(Move(kind: .burnt, event: e, change: change)) }
        if let (e, change) = turns.max(by: { $0.1 < $1.1 }), change >= moveSize { moves.append(Move(kind: .back, event: e, change: change)) }
        return moves.sorted { $0.event.ts < $1.event.ts }
    }

    /// How far a prompt has to move the fuse to turn the session: about what an orange dot burns.
    public static let moveSize = 0.12

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
