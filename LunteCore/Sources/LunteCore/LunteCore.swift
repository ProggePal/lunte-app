// The public API every piece codes against (docs/contract.md).
// Classifier, EventLog and Game live in their own files.
import Foundation

public enum Burn: String, Codable, Sendable { case none, tell, lose, test } // test: the onboarding phrase, never burns

/// One line of events.jsonl. Never holds prompt text.
public struct Event: Codable, Equatable, Sendable {
    public var v: Int
    public var ts: Double
    public var burn: Burn
    public var sid: String
    public init(ts: Double, burn: Burn, sid: String = "") { self.v = 1; self.ts = ts; self.burn = burn; self.sid = sid }
}

public struct Boom: Equatable, Sendable {
    public var id: String       // String(Int(ts * 1000))
    public var ts: Double
    public var litBy: [Event]   // the Sitting's Burns up to and including the Boom
}

public struct GameState: Equatable, Sendable {
    public var fuse: Int
    public var pieces: Int
    public var boomed: Bool
    public var sittingOpen: Bool
    public var currentBurns: [Event]
    public var booms: [Boom]
}
