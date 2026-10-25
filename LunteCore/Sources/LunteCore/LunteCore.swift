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
}

public struct GameState: Equatable, Sendable {
    /// How much heat the stick takes: 1 fresh, longer after a Boom, shorter after a calm Sitting.
    public var fuse: Double
    /// Heat² burned by the last 30 minutes of this Sitting.
    public var burned: Double
    public var boomed: Bool
    public var sittingOpen: Bool
    /// This Sitting's messages that are still burning.
    public var currentBurns: [Event]
    public var booms: [Boom]
    /// When the open Sitting began (its first message, or the first after a rest).
    public var sittingStart: Double?
    /// After a Boom: when the stick comes back if nothing else gets hot (10 quiet minutes, or 30 minutes after the last burn).
    public var freshAt: Double?

    /// The share of the stick that's left, 0...1.
    public var left: Double { boomed ? 0 : max(0, 1 - burned / fuse) }
}
