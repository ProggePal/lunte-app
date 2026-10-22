import XCTest
@testable import LunteCore

final class GameTests: XCTestCase {
    let t0 = 1_792_670_480.123

    /// Events a minute apart from t0, unless `at` gives offsets in seconds.
    func log(_ burns: [Burn], at offsets: [Double]? = nil) -> [Event] {
        burns.enumerated().map { Event(ts: t0 + (offsets?[$0.offset] ?? Double($0.offset) * 60), burn: $0.element) }
    }

    func test1OneLoseOnAFreshStickBooms() {
        let s = Game.replay(log([.lose]), now: t0 + 120)
        XCTAssertEqual(s.booms.count, 1)
        XCTAssertEqual(s.booms[0].ts, t0)
        XCTAssertEqual(s.booms[0].litBy.count, 1)
        XCTAssertEqual(s.fuse, 3)
        XCTAssertTrue(s.boomed)
        XCTAssertEqual(s.pieces, 0)
    }

    func test2TellTellNoBoom() {
        let s = Game.replay(log([.tell, .tell]), now: t0 + 120)
        XCTAssertTrue(s.booms.isEmpty)
        XCTAssertEqual(s.pieces, 1)
        XCTAssertEqual(Game.stickText(s), "🧨✨")
    }

    func test3TellThenLoseBooms() {
        XCTAssertEqual(Game.replay(log([.tell, .lose]), now: t0 + 120).booms.count, 1)
    }

    func test4OneBoomPerSitting() {
        let s = Game.replay(log([.lose, .lose, .lose, .lose, .tell]), now: t0 + 300)
        XCTAssertEqual(s.booms.count, 1)
        XCTAssertEqual(s.fuse, 3)
        XCTAssertEqual(s.currentBurns.count, 5)
    }

    func test5CalmSittingShortensFuseNeverBelowTwo() {
        let boom = log([.lose, .lose])
        XCTAssertEqual(Game.replay(boom, now: t0 + 10_000).fuse, 3) // a Booming Sitting doesn't shorten
        let calm1 = log([.none, .none], at: [4000, 4060])
        XCTAssertEqual(Game.replay(boom + calm1, now: t0 + 10_000).fuse, 2)
        let calm2 = log([.tell], at: [20_000])
        let s = Game.replay(boom + calm1 + calm2, now: t0 + 30_000)
        XCTAssertEqual(s.fuse, 2)
        XCTAssertEqual(s.pieces, 2)
    }

    func test6GapOf600StartsNewSitting() {
        // a Boom makes the fuse 3, a lose takes the next stick to the spark, then a tell 599 s or 600 s later
        let same = Game.replay(log([.lose, .lose, .tell], at: [0, 2000, 2599]), now: t0 + 2600)
        XCTAssertEqual(same.fuse, 3) // still the same Sitting
        let next = Game.replay(log([.lose, .lose, .tell], at: [0, 2000, 2600]), now: t0 + 2601)
        XCTAssertEqual(next.fuse, 2) // the calm Sitting closed and shortened the fuse
        XCTAssertEqual(next.pieces, 1)
    }

    func test7ClosedByNow() {
        let s = Game.replay(log([.tell]), now: t0 + 31 * 60)
        XCTAssertFalse(s.sittingOpen)
        XCTAssertEqual(s.pieces, s.fuse)
        XCTAssertTrue(s.currentBurns.isEmpty)
        let b = Game.replay(log([.lose, .lose]), now: t0 + 60 + 31 * 60)
        XCTAssertFalse(b.boomed)
        XCTAssertEqual(b.pieces, 3)
        XCTAssertEqual(Game.stickText(b), "🧨━━━")
        let empty = Game.replay([], now: t0)
        XCTAssertEqual(empty, GameState(fuse: 2, pieces: 2, boomed: false, sittingOpen: false, currentBurns: [], booms: []))
    }

    func test8StableBoomIds() {
        // second Sitting has fuse 3, so it takes two loses
        let events = log([.lose, .lose, .none, .lose, .lose, .lose], at: [0, 1, 2, 5000, 5001, 5002])
        let a = Game.replay(events, now: t0 + 9000), b = Game.replay(Array(events.reversed()), now: t0 + 9000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.booms.map(\.id), [String(Int(t0 * 1000)), String(Int((t0 + 5001) * 1000))])
    }

    func test9LoseBurnsTwoTellBurnsOne() {
        // two Booms make the fuse 4; then a lose takes two pieces, a tell one, and the next lose Booms
        let events = log([.lose, .lose, .lose, .lose, .tell, .lose], at: [0, 2000, 2001, 5000, 5001, 5002])
        XCTAssertEqual(Game.replay(Array(events.prefix(4)), now: t0 + 5000).pieces, 2)
        XCTAssertEqual(Game.replay(Array(events.prefix(5)), now: t0 + 5001).pieces, 1)
        let s = Game.replay(events, now: t0 + 5002)
        XCTAssertEqual(s.booms.count, 3)
        XCTAssertEqual(s.fuse, 5)
    }

    func testText() {
        var s = Game.replay([], now: t0)
        XCTAssertEqual(Game.stickText(s), "🧨━━")
        s.boomed = true
        XCTAssertEqual(Game.stickText(s), "💥")
        let at = { (h: Int, m: Int) in Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: h, minute: m))!.timeIntervalSince1970 }
        let boom = Boom(id: "x", ts: at(14, 40), litBy: [Event(ts: at(10, 12), burn: .tell), Event(ts: at(14, 40), burn: .lose)])
        XCTAssertEqual(Game.litByText(boom), "10:12 told off · 14:40 lost it")
    }
}

final class RestTests: XCTestCase {
    let t0 = 1_792_670_480.0

    func testRestEndsABoomedSittingWithoutShorteningTheFuse() {
        let s = Game.replay([Event(ts: t0, burn: .lose), Event(ts: t0 + 60, burn: .rest)], now: t0 + 61)
        XCTAssertFalse(s.boomed)
        XCTAssertFalse(s.sittingOpen)
        XCTAssertEqual(s.fuse, 3) // the Boom's +1 stays
        XCTAssertEqual(s.pieces, 3)
    }

    func testPromptAfterRestStartsFreshWithoutAnExtraCalmSitting() {
        let events = [Event(ts: t0, burn: .lose), Event(ts: t0 + 60, burn: .rest), Event(ts: t0 + 2000, burn: .tell)]
        let s = Game.replay(events, now: t0 + 2001)
        XCTAssertEqual(s.fuse, 3) // the empty stretch after the rest isn't a calm Sitting
        XCTAssertEqual(s.pieces, 2)
        XCTAssertTrue(s.sittingOpen)
    }

    func testRestOnACalmSittingShortensLikeABreak() {
        let events = [Event(ts: t0, burn: .lose), Event(ts: t0 + 700, burn: .tell), Event(ts: t0 + 760, burn: .rest)]
        XCTAssertEqual(Game.replay(events, now: t0 + 761).fuse, 2)
    }
}
