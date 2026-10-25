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
        Game.replay(events, now: now ?? t0 + 100_000).sittings[0]
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
        XCTAssertEqual(line([at(40, .lose), at(63, .lose)]), "Chain reaction at 15:03.")
        XCTAssertEqual(line([at(40, .lose), at(63, .lose), at(80), at(95)]), "Chain reaction at 15:03. Cooled off by 15:33.")
        XCTAssertEqual(line([at(40, .lose), at(50, .lose), at(79, .lose)]), "Meltdown at 15:19.")
    }

    func testAuraForCoolSessionsAndCloseCalls() {
        let calm = (0..<5).map { at(Double($0)) }
        XCTAssertEqual(Game.aura(first(calm)), 1) // a cool Sitting
        XCTAssertEqual(Game.aura(first(Array(calm.prefix(4)))), 0) // too short
        let close = [at(11, .tell), at(12, .tell), at(14, heat: 0, cool: 1)]
        XCTAssertEqual(Game.aura(first(close)), 2) // a close call, and too short to be a cool Sitting
        XCTAssertEqual(Game.aura(first(close + [at(15), at(16)])), 3) // both
        XCTAssertEqual(Game.aura(first([at(0, .lose)] + (1...5).map { at(Double($0)) })), 0) // a Boom, however long
        XCTAssertEqual(Game.roastAura, 5) // roasts come from the Club's reactions, not the replay
    }

    /// Guards docs/why.md#aura-not-work: a cool Sitting is worth the same at 5 prompts or 300, cool or not.
    func testAuraIgnoresPromptCount() {
        let five = (0..<5).map { at(Double($0)) }
        let long = (0..<300).map { at(Double($0) / 2, heat: 0, cool: 1) } // 300 cool prompts over two and a half hours
        XCTAssertEqual(first(long).coolPrompts, 300)
        XCTAssertEqual(Game.aura(first(long)), Game.aura(first(five)))
        XCTAssertEqual(Game.aura(first(long)), Game.coolSittingAura)
    }

    /// Vibes never go down: an open Sitting's cool point waits for the close, and a later Boom keeps the close call.
    func testAuraNeverGoesDown() {
        let calm = (0..<5).map { at(Double($0)) }
        XCTAssertEqual(Game.aura(first(calm, now: t0 + 600)), 0) // still open
        let close = [at(11, .tell), at(12, .tell), at(14, heat: 0, cool: 1)]
        XCTAssertEqual(Game.aura(first(close, now: t0 + 15 * 60)), 2) // a close call counts at once
        XCTAssertEqual(Game.aura(first(close + [at(16, .lose), at(17), at(18)])), 2) // and survives the Boom after it
    }
}
