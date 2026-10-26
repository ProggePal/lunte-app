import XCTest
@testable import LunteCore

/// What a Sitting leaves behind: one line built from the facts, and its aura.
final class SittingTests: XCTestCase {
    let t0 = 1_792_677_600.0 // 14:00 UTC
    let utc = TimeZone(identifier: "UTC")!

    /// A message `minutes` after 14:00.
    func at(_ minutes: Double, _ burn: Burn = .none, heat: Double? = nil, cool: Double? = nil) -> Event {
        Event(ts: t0 + minutes * 60, burn: burn, heat: heat, cool: cool)
    }

    func first(_ events: [Event], now: Double? = nil) -> Sitting {
        Game.replay(events, now: now ?? t0 + 100_000, timeZone: utc).sittings[0]
    }

    func line(_ events: [Event]) -> String { Game.sessionLine(first(events), timeZone: utc) }

    func testSessionLineCoolAllTheWay() {
        XCTAssertEqual(line((0..<42).map { at(Double($0)) }), "Cool all the way. 42 prompts.")
        XCTAssertEqual(line([at(0)]), "Cool all the way. 1 prompt.")
    }

    func testSessionLineCloseCall() {
        XCTAssertEqual(line([at(11, .tell), at(12, .tell), at(14, heat: 0, cool: 1)]), "Close call at 14:12. Cooled off.")
        let twice = [at(10, .tell), at(11, .tell), at(12, heat: 0, cool: 1), at(20, .tell), at(21, .tell), at(22, heat: 0, cool: 1)]
        XCTAssertEqual(first(twice).closeCalls.count, 2)
        XCTAssertEqual(line(twice), "2 close calls, the last at 14:21. Cooled off.")
    }

    /// Guards docs/why.md#peak-end.
    func testSessionLineEndsOnRecovery() {
        XCTAssertEqual(line([at(12, .lose)]), "Boomed at 14:12.") // one message, and gone
        let slow = [at(2, .tell), at(7, heat: 0.5), at(12, .lose)] // heat building for 10 minutes
        XCTAssertEqual(line(slow), "Slow burn. Boomed at 14:12.")
        XCTAssertEqual(line(slow + [at(30), at(45)]), "Slow burn. Boomed at 14:12. Cooled off by 14:42.") // still at it after the burns cooled
        XCTAssertEqual(line(slow + [at(30)]), "Slow burn. Boomed at 14:12.") // left before they had
    }

    func testSessionLineNamesTheTopTier() {
        XCTAssertEqual(line([at(40, .lose), at(63, heat: 0.8)]), "Chain reaction at 15:03.")
        XCTAssertEqual(line([at(40, .lose), at(63, heat: 0.8), at(80), at(95)]), "Chain reaction at 15:03. Cooled off by 15:33.")
        XCTAssertEqual(line([at(40, .lose), at(50, .tell), at(65, .tell), at(69, .lose)]), "Meltdown at 15:09.")
    }

    /// Guards docs/why.md#aura-not-work: one award per Sitting, the best thing that happened.
    func testAuraOneAwardPerSession() {
        let calm = (0..<5).map { at(Double($0)) }
        XCTAssertEqual(Game.aura(first(calm)), 1) // a cool Sitting
        XCTAssertEqual(Game.aura(first(Array(calm.prefix(4)))), 0) // too short
        let close = [at(11, .tell), at(12, .tell), at(14, heat: 0, cool: 1)]
        XCTAssertEqual(Game.aura(first(close)), 3) // a close call, and too short to be a cool Sitting
        XCTAssertEqual(Game.aura(first(close + [at(15), at(16)])), 3) // cool too, but one award
        let twice = [at(10, .tell), at(11, .tell), at(12, heat: 0, cool: 1), at(20, .tell), at(21, .tell), at(22, heat: 0, cool: 1)]
        XCTAssertEqual(first(twice).closeCalls.count, 2)
        XCTAssertEqual(Game.aura(first(twice)), 3) // two close calls, one award
        XCTAssertEqual(Game.aura(first([at(0, .lose)] + (1...5).map { at(Double($0)) })), 0) // a Boom, however long
        XCTAssertEqual(first(close).aura, 3) // the replay stores it
        XCTAssertEqual(Game.roastAura, 8) // roasts come from the Club's reactions, not the replay
    }

    /// Guards docs/why.md#aura-not-work: a cool Sitting earns its point at most once per local day, so more Sittings
    /// don't mean more aura. A close call doesn't use up the day's point.
    func testCoolSessionAuraOncePerLocalDay() {
        func cool(_ from: Double) -> [Event] { (0..<5).map { at(from + Double($0)) } }
        let tomorrow = 24 * 60.0
        let closeAndCool = [at(tomorrow, .tell), at(tomorrow + 1, .tell), at(tomorrow + 3, heat: 0, cool: 1),
                            at(tomorrow + 4), at(tomorrow + 5)]
        let events = cool(0) + cool(60) + cool(120) + closeAndCool + cool(tomorrow + 60)
        XCTAssertEqual(Game.replay(events, now: t0 + 3 * 86_400, timeZone: utc).sittings.map(Game.aura), [1, 0, 0, 3, 1])
        let east = TimeZone(secondsFromGMT: 34_200)! // UTC+9:30, where 14:00 and 15:00 UTC are 23:30 and 00:30
        XCTAssertEqual(Game.replay(events, now: t0 + 3 * 86_400, timeZone: east).sittings.prefix(3).map(Game.aura), [1, 1, 0])
    }

    /// Guards docs/why.md#aura-not-work: a cool Sitting is worth the same at 5 prompts or 300, cool or not.
    func testAuraIgnoresPromptCount() {
        let five = (0..<5).map { at(Double($0)) }
        let long = (0..<300).map { at(Double($0) / 2, heat: 0, cool: 1) } // 300 cool prompts over two and a half hours
        XCTAssertEqual(first(long).coolPrompts, 300)
        XCTAssertEqual(Game.aura(first(long)), Game.aura(first(five)))
        XCTAssertEqual(Game.aura(first(long)), Game.coolSittingAura)
    }

    /// Aura never goes down: an open Sitting's cool point waits for the close, and a later Boom keeps the close call.
    func testAuraNeverGoesDown() {
        let calm = (0..<5).map { at(Double($0)) }
        XCTAssertEqual(Game.aura(first(calm, now: t0 + 600)), 0) // still open
        let close = [at(11, .tell), at(12, .tell), at(14, heat: 0, cool: 1)]
        XCTAssertEqual(Game.aura(first(close, now: t0 + 15 * 60)), 3) // a close call counts at once
        XCTAssertEqual(Game.aura(first(close + [at(16, .lose), at(17), at(18)])), 3) // and survives the Boom after it
    }

    /// Guards docs/why.md#never-fake-reactions: the session's line is the replay's fuse at every step, never closer.
    func testFuseLineFollowsTheReplay() {
        let events = [at(0, heat: 0.6), at(10, heat: 0.7), at(20, heat: 0, cool: 1), at(25)]
        let line = Game.fuseLine(first(events), events, now: t0 + 100_000)
        XCTAssertEqual(line.count, 7) // three prompts that burn or mend (the first is the start), three cooling off, the close
        for (ts, left) in line.dropLast() {
            XCTAssertEqual(left, Game.replay(events.filter { $0.ts <= ts }, now: ts, timeZone: utc).left, accuracy: 1e-9)
        }
        XCTAssertEqual(line.last?.left, 1) // full again at the close
    }

    /// And when cool grew it: the line climbs past 1, burns come off the grown fuse, and the session says how far it grew.
    func testFuseLineShowsWhatCoolGrew() {
        let events = [at(0, heat: 0, cool: 1), at(5, heat: 0, cool: 0.8), at(10, heat: 0.6), at(20, heat: 0.5, cool: 0.5), at(45)]
        let s = first(events), line = Game.fuseLine(s, events, now: t0 + 100_000)
        for (ts, left) in line.dropLast() {
            XCTAssertEqual(left, Game.replay(events.filter { $0.ts <= ts }, now: ts, timeZone: utc).left, accuracy: 1e-9, "at \(ts)")
        }
        XCTAssertEqual(line.map(\.left).max(), Game.full)
        XCTAssertEqual(line.last?.left, 1) // fresh at the close
        XCTAssertEqual(Game.sessionLine(s, timeZone: utc), "Grew to full. 5 prompts.")
        XCTAssertEqual(self.line([at(0, heat: 0, cool: 0.6), at(1)]), "Grew to 109 %. 2 prompts.")
        // Prompts that land at the same moment count one after another, as the replay counts them.
        let twins = [at(0, heat: 0.4), at(3, heat: 0, cool: 0.5), at(3, heat: 0, cool: 0.5), at(3, heat: 0, cool: 0.5)]
        let steps = Game.fuseLine(first(twins), twins, now: t0 + 100_000)
        XCTAssertEqual(steps.first { $0.ts == t0 + 180 }!.left, Game.replay(twins, now: t0 + 180, timeZone: utc).left, accuracy: 1e-9)
    }

    func testFuseLineIsEmptyFromTheBoom() {
        let events = [at(2, .tell), at(7, heat: 0.5), at(12, .lose), at(14, .tell)]
        let s = first(events), boom = s.boom!.ts
        let line = Game.fuseLine(s, events, now: t0 + 100_000)
        XCTAssertGreaterThan(line.first { $0.ts == t0 + 7 * 60 }!.left, 0)
        XCTAssertEqual(line.filter { $0.ts >= boom }.dropLast().map(\.left).max(), 0)
        XCTAssertEqual(line.last?.left, 1) // a fresh fuse at the close
    }

    func testWordSaysWhatTheFuseDid() {
        func word(_ events: [Event], at minutes: Double) -> String {
            Game.word(Game.replay(events, now: t0 + minutes * 60, timeZone: utc), now: t0 + minutes * 60)
        }
        XCTAssertEqual(word([at(0)], at: 1), "Cool")
        XCTAssertEqual(word([at(0, heat: 0.5)], at: 1), "Burning")
        XCTAssertEqual(word([at(0, heat: 0.5)], at: 6), "Cooling off")
        XCTAssertEqual(word([at(0, heat: 0.5), at(8, heat: 0.5), at(11, heat: 0.4)], at: 12), "Slow burn")
        XCTAssertEqual(word([at(0, .tell), at(1, .tell)], at: 2), "Last third")
    }
}
