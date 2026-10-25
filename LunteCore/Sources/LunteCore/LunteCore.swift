// The public API every piece codes against (docs/contract.md).
// Classifier, EventLog and Game live in their own files.
import Foundation

/// test: the onboarding phrase. rest: written by the app when a hurried break ends.
/// heat: written by the app, the model's heat and cool for the prompt logged at the same ts; merged into it on read.
public enum Burn: String, Codable, Sendable { case none, tell, lose, test, rest, heat }

/// One line of events.jsonl. Never holds prompt text.
public struct Event: Codable, Equatable, Sendable {
    public var v: Int
    public var ts: Double
    public var burn: Burn
    public var sid: String
    /// The hook handed the prompt to the app's model, so a heat line should follow.
    public var rated: Bool?
    /// 0...1, the model's rating. Heat is anger, not volume.
    public var heat: Double?
    /// 0...1, how much you talk to your agent like a best bud: slang, banter, hype, happy swearing. Nil without a
    /// trained cool model, and in logs from before cool.
    public var cool: Double?
    /// The model's read of your mood ("frustrated", "hyped", …), for the vibe line.
    public var mood: String?
    /// What the message is about, one word from `Vibe.topics` ("design", "code", …), for the vibe line. Never text.
    public var topic: String?

    public init(ts: Double, burn: Burn, sid: String = "", rated: Bool? = nil, heat: Double? = nil, cool: Double? = nil,
                mood: String? = nil, topic: String? = nil) {
        self.v = 1; self.ts = ts; self.burn = burn; self.sid = sid; self.rated = rated; self.heat = heat; self.cool = cool
        self.mood = mood; self.topic = topic
    }

    /// Handed to the model and still waiting for its rating, for at most `Game.ratingWait`.
    public func awaitingRating(at now: Double) -> Bool { heat == nil && rated == true && now - ts < Game.ratingWait }

    /// How hot this message ran, 0...1: the model's rating, or the word list's when there is none (telling it off 0.6,
    /// losing it 1). A rated message still waiting for its rating counts as cool, so the word list can't Boom first.
    public func heat(at now: Double) -> Double {
        if let heat { return heat }
        if awaitingRating(at: now) { return 0 }
        switch burn {
        case .tell: return 0.6
        case .lose: return 1
        default: return 0
        }
    }
}

public struct Boom: Equatable, Sendable {
    public var id: String       // String(Int(ts * 1000))
    public var ts: Double
    public var litBy: [Event]   // the burns still burning when it blew, up to and including the Boom
    /// When more heat stepped it up a tier: each further half of the stick that blew, within 30 minutes of the Boom,
    /// is Chain reaction, then Meltdown. A prompt that steps up two tiers is here twice. Still one Boom.
    public var escalations: [Double] = []

    /// 1 Boom, 2 Chain reaction, 3 Meltdown (`Game.tiers`).
    public var tier: Int { 1 + escalations.count }
}

/// The stick got into its last third and climbed back out without a Boom in between. One per dip.
public struct CloseCall: Equatable, Sendable {
    /// When it got into the last third.
    public var ts: Double
    /// When it climbed back out: a cool prompt mended it, or the burn that put it there cooled off.
    public var cooled: Double
}

/// A session in GAME.md: from your first prompt until 30 minutes without one, or a rest. Facts only, and it stays on
/// this Mac.
public struct Sitting: Equatable, Sendable {
    public var start: Double
    /// Its last prompt so far. It closes `Game.sittingGap` after this, unless a rest closed it sooner.
    public var end: Double
    public var prompts = 0
    /// The hottest prompt, 0...1.
    public var peakHeat = 0.0
    /// Prompts with cool of at least `Game.coolPrompt`.
    public var coolPrompts = 0
    /// Its one Boom, with the escalations; nil if it never blew.
    public var boom: Boom?
    public var closeCalls: [CloseCall] = []
    /// The last prompt that burned.
    public var lastBurn: Double?
    /// Still going: the last prompt was less than `Game.sittingGap` ago.
    public var isOpen = false
    /// Its one award, without roasts (`Game.aura`): set by the replay, which knows the other Sittings that day.
    public var aura = 0

    /// 0 without a Boom, else `boom.tier`.
    public var tier: Int { boom?.tier ?? 0 }
    /// When the last burn had cooled off, if you were still at it by then: the recovery after a Boom.
    // ponytail: by the clock only; cool messages that mend the burn sooner don't bring it forward
    public var cooledOff: Double? { lastBurn.map { $0 + Game.cooling }.flatMap { $0 <= end ? $0 : nil } }
}

public struct GameState: Equatable, Sendable {
    /// How much heat the stick takes: 1 fresh, longer after a Boom, shorter after a calm workday. An open Sitting
    /// keeps its stick; after a Boom, or with no Sitting open, it's the next one.
    public var fuse: Double
    /// What's burning in this Sitting: heat² from the last 30 minutes, less what cool mended, never below 0. After a
    /// Boom it starts again from 0 and counts toward the tiers.
    public var burned: Double
    /// Blown: the Sitting has Boomed, and stays blown until it closes.
    public var boomed: Bool
    public var sittingOpen: Bool
    /// This Sitting's messages that are still burning, from before and after a Boom.
    public var currentBurns: [Event]
    public var booms: [Boom]
    /// When the open Sitting began (its first message, or the first after a rest).
    public var sittingStart: Double?
    /// After a Boom: when the stick comes back if nothing else happens, which is when the Sitting closes (30 quiet
    /// minutes after the last prompt).
    public var freshAt: Double?
    /// Every Sitting, oldest first: the closed ones, then the open one.
    public var sittings: [Sitting] = []

    /// The share of the stick that's left, 0...1.
    public var left: Double { boomed ? 0 : max(0, 1 - burned / fuse) }
    /// The open Sitting, if there is one.
    public var sitting: Sitting? { sittings.last.flatMap { $0.isOpen ? $0 : nil } }
    /// Every close call, oldest first.
    public var closeCalls: [CloseCall] { sittings.flatMap(\.closeCalls) }
}
