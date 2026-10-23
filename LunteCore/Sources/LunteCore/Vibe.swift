// This session's vibe: one dry line about your last 30 minutes (contract §4, §8). Shown in the popover only, never
// sent. Stock vibes ship with the app and rotate in with updates; your AI can add personal ones at fuse setup.
import Foundation

public struct Vibe: Codable, Equatable, Hashable, Sendable {
    /// How hot the last 30 minutes ran. A vibe is only picked from the band you're in.
    public enum Band: String, Codable, CaseIterable, Sendable { case calm, warm, hot, explosive }

    public var emoji: String
    public var label: String
    /// The longer line on hover.
    public var story: String
    public var band: Band
    /// When it fits, in a few words. Guides whoever writes the vibe; Laya picks by label for now (see `Scorer.pickVibe`).
    public var when: String
    /// The topic a vibe is about, from `topics`, or nil (or "any" in vibes.json) for one that fits any topic. Your AI
    /// sets it at fuse setup; vibes without one are tagged once by Laya. Stock vibes are about mood and time: none.
    public var topic: String?

    /// What a message can be about. One word per message is all that's kept.
    public static let topics: [(name: String, about: String)] = [
        ("code", "code, bugs, tests"), ("design", "visuals, layout, UI"), ("writing", "copy, text, docs"),
        ("business", "pricing, sales, plans"), ("voice", "audio, speech, voice"), ("shipping", "commit, deploy, release"),
        ("ideas", "brainstorming, thinking aloud"), ("other", "anything else"),
    ]

    /// The topic most of the last 30 minutes were about: at least 3 messages and 40% of those with a topic. Else nil.
    public static func topic(_ recent: [Event]) -> String? {
        let named = recent.compactMap(\.topic).filter { $0 != "other" }
        guard let top = Dictionary(named.map { ($0, 1) }, uniquingKeysWith: +).max(by: { $0.value < $1.value }),
              top.value >= 3, Double(top.value) >= 0.4 * Double(recent.compactMap(\.topic).count) else { return nil }
        return top.key
    }

    public init(_ emoji: String, _ label: String, _ band: Band, when: String, story: String) {
        self.emoji = emoji; self.label = label; self.band = band; self.when = when; self.story = story
    }

    /// Fewer messages than this in 30 minutes, and there's no vibe yet: "Reading the room…".
    public static let minimumMessages = 5

    public static let stock: [Vibe] = [
        Vibe("☕", "Perfectly civil", .calm, when: "polite, steady work", story: "Polite, productive, nothing to report."),
        Vibe("🧊", "Suspiciously calm", .calm, when: "many messages, not a raised voice", story: "Thirty messages without a raised voice. Who are you?"),
        Vibe("✨", "Dangerously enthusiastic", .calm, when: "excited, hyped, thankful", story: "High spirits. Someone check on the codebase."),
        Vibe("🕊️", "Remarkably recovered", .calm, when: "calm again soon after a Boom", story: "There was an incident. We don't talk about it."),
        Vibe("🎧", "In the zone", .calm, when: "lots of quick, calm messages", story: "Short messages, no drama. Flow, apparently."),
        Vibe("🌙", "Late-night grind", .calm, when: "calm work late at night", story: "Nobody else is awake. The assistant doesn't mind."),
        Vibe("🌵", "A little prickly", .warm, when: "one or two irritated messages", story: "Mostly fine. A thorn or two."),
        Vibe("⚖️", "Firm but fair", .warm, when: "several firm corrections", story: "Clear instructions, delivered with feeling."),
        Vibe("😒", "Mildly offended", .warm, when: "one sharp message, otherwise calm", story: "Something was said. It has been noted."),
        Vibe("🔁", "Repeating yourself. Again.", .warm, when: "the same instruction, again", story: "You said it once. You said it twice."),
        Vibe("🌡️", "Running rather hot", .hot, when: "heat building over several messages", story: "Productive, technically. The fuse has opinions."),
        Vibe("🧨", "Barely contained", .hot, when: "very little fuse left", story: "The fuse is short and getting shorter."),
        Vibe("😤", "Testing human patience", .hot, when: "frustrated and repeating", story: "What began as productive work slowly became a test of human patience."),
        Vibe("💥", "Rather explosive", .explosive, when: "it just blew", story: "It went off. The room may have noticed."),
        Vibe("🔥", "Still smouldering", .explosive, when: "still heated after the Boom", story: "The dust hasn't settled, and neither have you."),
    ]

    /// The band your last 30 minutes are in.
    public static func band(_ state: GameState, recent: [Event], now: Double) -> Band {
        if state.boomed { return .explosive }
        if state.left <= 0.5 { return .hot }
        return recent.contains { $0.heat(at: now) >= 0.35 } ? .warm : .calm
    }

    /// Up to six vibes for the band: your own first, then stock, rotated by `seed` so the same moment gets the same
    /// shortlist and different sessions get different ones. Six keeps Laya's question inside its 128 tokens.
    /// A vibe about a topic only makes the list when the session is about that topic, and then it goes first.
    public static func candidates(_ band: Band, personal: [Vibe], seed: Int, topic: String? = nil) -> [Vibe] {
        func rotate(_ v: [Vibe], _ n: Int) -> [Vibe] { v.isEmpty ? [] : Array((v + v).dropFirst(abs(seed) % v.count).prefix(min(n, v.count))) }
        let inBand = personal.filter { $0.band == band }
        let onTopic = topic.map { t in inBand.filter { $0.topic == t } } ?? []
        let mine = Array((rotate(onTopic, 3) + rotate(inBand.filter { $0.topic == nil }, 3)).prefix(3))
        let theirs = stock.filter { s in s.band == band && !mine.contains { $0.label == s.label } } // labels must differ for Laya
        return mine + rotate(theirs, 6 - mine.count)
    }

    /// The last 30 minutes in a few words, most important first, for Laya. No message text.
    public static func summary(_ state: GameState, recent: [Event], now: Double) -> String {
        let heats = recent.map { Game.heatWord($0.heat(at: now)) }
        let moods = Dictionary(recent.compactMap(\.mood).map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \($0.value)" }
        let lastFive = recent.filter { now - $0.ts < 300 }.count
        let time = Date(timeIntervalSince1970: now).formatted(.dateTime.weekday(.wide).hour().minute())
        var parts = ["\(recent.count) messages in 30 minutes, \(lastFive) in the last 5", "heat: " + heats.suffix(8).joined(separator: ", ")]
        if !moods.isEmpty { parts.append("moods: " + moods.joined(separator: ", ")) }
        let topics = Dictionary(recent.compactMap(\.topic).filter { $0 != "other" }.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value > $1.value }.prefix(2).map { "\($0.key) \($0.value)" }
        if !topics.isEmpty { parts.append("topics: " + topics.joined(separator: ", ")) }
        parts.append(state.boomed ? "it just blew" : "fuse \(Int((state.left * 100).rounded()))% left")
        if let boom = state.booms.last, !state.boomed, now - boom.ts < 3600 { parts.append("a Boom \(Int((now - boom.ts) / 60)) minutes ago") }
        parts.append(time)
        return parts.joined(separator: ". ")
    }

    /// Without the model: the first rule that matches, from the stock vibes. Same `recent` as `summary`.
    public static func of(_ state: GameState, recent: [Event], boomedWithinHour: Bool, now: Double) -> Vibe {
        let heats = recent.map { $0.heat(at: now) }
        let warm = heats.filter { $0 >= 0.35 && $0 < 0.6 }.count
        let happy = recent.filter { $0.mood == "hyped" || $0.mood == "grateful" }.count
        let pick = { (label: String) in stock.first { $0.label == label }! }
        if state.boomed { return pick("Rather explosive") }
        if state.left <= 0.2 { return pick("Barely contained") }
        if state.left <= 0.5 { return pick("Running rather hot") }
        if heats.contains(where: { $0 >= 0.6 }) { return pick("Mildly offended") }
        if warm >= 3 { return pick("Firm but fair") }
        if warm > 0 { return pick("A little prickly") }
        if boomedWithinHour { return pick("Remarkably recovered") }
        if happy >= 2 { return pick("Dangerously enthusiastic") }
        if recent.count >= 30 { return pick("Suspiciously calm") }
        return pick("Perfectly civil")
    }
}

/// vibes.json, written by your AI at fuse setup: your personal vibes, found by playing.
public struct FuseVibes: Codable, Equatable, Sendable {
    public var lunte: String
    public var v: Int
    public var made: String?
    public var vibes: [Vibe]

    /// What's wrong with it, or [] when it's fine.
    public var problems: [String] {
        var out: [String] = []
        if lunte != "fuse-vibes" { out.append(#""lunte" must be "fuse-vibes""#) }
        if v != 1 { out.append(#""v" must be 1"#) }
        let long = vibes.filter { $0.label.split(separator: " ").count > 5 || $0.when.split(separator: " ").count > 14 }.count
        if long > 0 { out.append("\(long) vibes have a label over 5 words or a \"when\" over 14 words") }
        if vibes.contains(where: { $0.label.isEmpty || $0.emoji.isEmpty || $0.story.isEmpty }) { out.append("every vibe needs an emoji, a label and a story") }
        let topics = Set(Vibe.topics.map(\.name)).subtracting(["other"]).union(["any"])
        let badTopics = vibes.compactMap(\.topic).filter { !topics.contains($0) }.count
        if badTopics > 0 { out.append("\(badTopics) vibes have a topic that isn't code, design, writing, business, voice, shipping, ideas or any") }
        let missing = Vibe.Band.allCases.filter { b in !vibes.contains { $0.band == b } }
        if !missing.isEmpty { out.append("no vibes for: " + missing.map(\.rawValue).joined(separator: ", ")) }
        return out
    }
}
