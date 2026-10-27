import XCTest
@testable import LunteCore

/// Guards docs/why.md#session-names: a finished session's name, story, cool and aura, from sample sessions played
/// through the real game.
final class StoryTests: XCTestCase {
    let t0 = 1_792_677_600.0 // Thursday 22 Oct 2026, 14:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    /// A prompt `minutes` after `start`.
    func at(_ minutes: Double, heat: Double = 0, cool: Double = 0, topic: String? = nil, start: Double? = nil) -> Event {
        var e = Event(ts: (start ?? t0) + minutes * 60, burn: .none, heat: heat, cool: cool)
        e.topic = topic
        return e
    }

    /// The session these prompts make, its prompts, and its fuse after each, as `Game.fuseLine` gives it.
    func told(_ events: [Event]) -> Story.Told {
        let s = Game.replay(events, now: events.last!.ts + 100_000, timeZone: utc.timeZone).sittings[0]
        let line = events.indices.map { i in (ts: events[i].ts, left: Game.replay(Array(events[...i]), now: events[i].ts, timeZone: utc.timeZone).left) }
        return (s, events, [(s.start, 1.0)] + line)
    }

    let calm = (0..<8).map { Double($0) }
    func energy(_ events: [Event]) -> Story.Energy { let t = told(events); return Story.energy(t.sitting, t.line) }

    func testEnergyIsWhatTheFuseDid() {
        XCTAssertEqual(energy(calm.map { at($0) }), .steady)
        XCTAssertEqual(energy(calm.map { at($0, cool: $0 < 2 ? 1 : 0) }), .buzzing) // cool grew it
        XCTAssertEqual(energy(calm.map { at($0, heat: $0 == 3 ? 0.75 : 0) }), .intense) // burned about half
        XCTAssertEqual(energy(calm.map { at($0, heat: $0 == 3 ? 1 : 0) }), .boom)
    }

    func testTheMovesAreThePromptsThatTurnedIt() {
        func moves(_ events: [Event]) -> [(Story.Move.Kind, Double)] {
            let s = Game.replay(events, now: events.last!.ts + 100_000, timeZone: utc.timeZone).sittings[0]
            return Story.moves(s, events, Game.fuseLine(s, events, now: events.last!.ts + 100_000)).map { ($0.kind, $0.event.ts) }
        }
        XCTAssertTrue(moves(calm.map { at($0) }).isEmpty) // steady: nothing turned it
        XCTAssertTrue(moves(calm.map { at($0, heat: 0.3) }).isEmpty) // grey dots burn under a move's worth
        // Burnt, then brought back, in that order.
        let back = moves([at(0), at(1, heat: 0.5), at(2, heat: 0.8), at(3, cool: 1), at(4)])
        XCTAssertEqual(back.map(\.0), [.burnt, .back])
        XCTAssertEqual(back.map(\.1), [t0 + 120, t0 + 180])
        // The prompt that set it off, and the biggest burn before it, but never the same prompt twice.
        let boom = moves([at(0, heat: 0.7), at(1), at(2, heat: 0.75)])
        XCTAssertEqual(boom.map(\.0), [.burnt, .setItOff])
        XCTAssertEqual(moves([at(0), at(1, heat: 1), at(2, heat: 1)]).map(\.0), [.setItOff]) // after the Boom, nothing burns
    }

    func testTheActivityIsTheTopicElseTheTime() {
        let design = (0..<5).map { at(Double($0), topic: $0 < 4 ? "design" : "code") }
        XCTAssertEqual(Story.activity(told(design).sitting, design, calendar: utc), "design")
        let one = { (hour: Double, day: Double) in [self.at(0, start: self.t0 + (hour - 14) * 3600 + day * 86400)] }
        XCTAssertEqual(Story.activity(told(one(7, 0)).sitting, one(7, 0), calendar: utc), "early")
        XCTAssertEqual(Story.activity(told(one(23, 0)).sitting, one(23, 0), calendar: utc), "late")
        XCTAssertEqual(Story.activity(told(one(7, 2)).sitting, one(7, 2), calendar: utc), "weekend") // a Saturday morning
        XCTAssertEqual(Story.activity(told(one(14, 0)).sitting, one(14, 0), calendar: utc), "day")
    }

    /// A day of five sessions: every name fits what happened, yours come first when they fit, and none repeats that day.
    func testNamesFitAndDontRepeatInADay() {
        let hour = { (h: Double) in self.t0 + (h - 14) * 3600 }
        let shipping = (0..<6).map { at(Double($0), heat: $0 == 3 ? 0.75 : 0, topic: "shipping", start: hour(9)) }
        let boom = [at(0, start: hour(11)), at(1, heat: 1, start: hour(11)), at(2, start: hour(11))]
        let calmA = (0..<6).map { at(Double($0), start: hour(13)) }, calmB = (0..<6).map { at(Double($0), start: hour(15)) }
        let quick = [at(0, start: hour(17))]
        let mine = [Vibe("🚀", "Release day nerves", .hot, when: "shipping, running short", story: "s"), Vibe("🎨", "Mine for design", .calm, when: "w", story: "s")]
        var tagged = mine
        tagged[0].topic = "shipping"
        tagged[1].topic = "design"
        let names = Story.names([shipping, boom, calmA, calmB, quick].map(told), personal: tagged, calendar: utc)
        XCTAssertEqual(names[0], "Release day nerves") // yours, and it's about shipping
        XCTAssertTrue(Story.stock["day"]![.boom]!.contains(names[1]))
        XCTAssertTrue(Story.stock["day"]![.steady]!.contains(names[2]))
        XCTAssertTrue(Story.stock["day"]![.steady]!.contains(names[3]))
        XCTAssertNotEqual(names[2], names[3]) // never twice a day
        XCTAssertTrue(Story.short.contains(names[4]))
        XCTAssertFalse(names.contains("Mine for design")) // a design name waits for a design session
        // The same log names the same way, every time.
        XCTAssertEqual(Story.names([shipping, boom, calmA, calmB, quick].map(told), personal: tagged, calendar: utc), names)
    }

    /// Enough names for everyone, and none that scolds: every kind of work and time of day has at least three for each
    /// energy, all different, 2 to 6 words.
    func testStockNamesAreManyAndKind() {
        let all = Story.stock.values.flatMap { $0.values.flatMap { $0 } } + Story.short
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertGreaterThanOrEqual(all.count, 140)
        for (activity, byEnergy) in Story.stock {
            for energy in Story.Energy.allCases { XCTAssertGreaterThanOrEqual(byEnergy[energy]?.count ?? 0, 3, "\(activity) \(energy)") }
        }
        for name in all {
            XCTAssertTrue((1...6).contains(name.split(separator: " ").count), name)
            XCTAssertFalse(["angry", "furious", "rage", "idiot", "fail", "blame", "your fault"].contains { name.lowercased().contains($0) }, name)
        }
        XCTAssertEqual(Set(Story.stock.keys), Set(Vibe.topics.map(\.name)).subtracting(["other"]).union(["early", "late", "weekend", "day"]))
    }
}
