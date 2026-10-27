import XCTest
@testable import LunteCore

final class GameTests: XCTestCase {
    let t0 = 1_792_670_480.123 // a Thursday, 12:01 UTC
    let utc = TimeZone(identifier: "UTC")!

    /// Events a minute apart from t0, unless `at` gives offsets in seconds.
    func log(_ burns: [Burn], at offsets: [Double]? = nil) -> [Event] {
        burns.enumerated().map { Event(ts: t0 + (offsets?[$0.offset] ?? Double($0.offset) * 60), burn: $0.element) }
    }

    func test1OneLoseOnAFreshStickBooms() {
        let s = Game.replay(log([.lose]), now: t0 + 120)
        XCTAssertEqual(s.booms.count, 1)
        XCTAssertEqual(s.booms[0].ts, t0)
        XCTAssertEqual(s.booms[0].litBy.count, 1)
        XCTAssertEqual(s.fuse, 1.75)
        XCTAssertTrue(s.boomed)
        XCTAssertEqual(s.left, 0)
    }

    func test2TellTellNoBoom() {
        let s = Game.replay(log([.tell, .tell]), now: t0 + 120)
        XCTAssertTrue(s.booms.isEmpty)
        XCTAssertEqual(s.burned, 0.72, accuracy: 1e-9) // telling it off is heat 0.6, so 0.36 each
        XCTAssertEqual(Game.stickText(s), "🧨✨")
    }

    func test3TooMuchHeatBlows() {
        XCTAssertEqual(Game.replay(log([.tell, .lose]), now: t0 + 120).booms.count, 1)
        XCTAssertEqual(Game.replay(log([.tell, .tell, .tell]), now: t0 + 180).booms.count, 1) // 1.08 of a 1.0 fuse
    }

    func test4OneBoomUntilTheSittingCloses() {
        let s = Game.replay(log([.lose, .lose, .lose, .lose, .tell]), now: t0 + 300)
        XCTAssertEqual(s.booms.count, 1)
        XCTAssertEqual(s.fuse, 1.75)
        XCTAssertEqual(s.currentBurns.count, 5)
    }

    /// Guards docs/why.md#rare-booms: +0.75 per Boom, −0.25 per calm workday (a local day with prompts and no Boom),
    /// never below 1. A calm Sitting on its own changes nothing.
    func testThermostatShrinksPerCalmWorkday() {
        let day = 86_400.0
        func fuse(_ events: [Event], at now: Double) -> Double { Game.replay(events, now: now, timeZone: utc).fuse }
        let thursday = log([.lose, .none, .none], at: [0, 4000, 8000]) // a Boom, then two calm Sittings
        XCTAssertEqual(fuse(thursday, at: t0 + 10_000), 1.75)
        XCTAssertEqual(fuse(thursday, at: t0 + day), 1.75) // a day that Boomed doesn't shrink it
        let friday = log([.tell], at: [day])
        XCTAssertEqual(fuse(thursday + friday, at: t0 + day + 60), 1.75) // Friday isn't over
        XCTAssertEqual(fuse(thursday + friday, at: t0 + 2 * day), 1.5) // Friday was calm
        XCTAssertEqual(fuse(thursday + friday, at: t0 + 4 * day), 1.5) // a day without prompts isn't a workday
        let more = log([.none, .none, .none, .none], at: [2, 3, 4, 5].map { $0 * day })
        XCTAssertEqual(fuse(thursday + friday + more, at: t0 + 9 * day), 1) // never below 1
        XCTAssertEqual(fuse(thursday + log([.test], at: [day]), at: t0 + 2 * day), 1.75) // the onboarding phrase isn't work

        // A Sitting keeps its stick past midnight; the next one gets the shorter stick.
        let midnight = (t0 / day + 2).rounded(.down) * day // Friday to Saturday
        let late = thursday + friday + [Event(ts: midnight - 600, burn: .lose), Event(ts: midnight + 600, burn: .none, heat: 0.775)]
        let open = Game.replay(late, now: midnight + 660, timeZone: utc)
        XCTAssertEqual(open.booms.count, 1) // 1.6 burned: under its 1.75, over the 1.5 to come
        XCTAssertTrue(open.sittingOpen)
        XCTAssertEqual(open.fuse, 1.75)
        XCTAssertEqual(fuse(late + [Event(ts: midnight + 4000, burn: .none)], at: midnight + 4060), 1.5)
    }

    /// Guards docs/why.md#rare-booms: a calm workday is a local day, however long. In Europe/Oslo the clocks go back
    /// on Sunday 25 Oct 2026, so that day has 25 hours, and it still shortens the fuse once.
    func testThermostatShrinksOncePerCalmDayAcrossDST() {
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oslo
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Double {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!.timeIntervalSince1970
        }
        XCTAssertEqual(at(26, 0) - at(25, 0), 25 * 3600) // the clocks go back an hour
        let events = [Event(ts: at(24, 12), burn: .lose), // Saturday Booms: 1.75
                      Event(ts: at(25, 0, 30), burn: .none), Event(ts: at(25, 23, 15), burn: .none)] // a calm Sunday, end to end
        func fuse(at now: Double) -> Double { Game.replay(events, now: now, timeZone: oslo).fuse }
        XCTAssertEqual(fuse(at: at(25, 23, 50)), 1.75) // Sunday isn't over, though 24 hours of it have gone
        XCTAssertEqual(fuse(at: at(26, 23, 30)), 1.5) // one shrink for Sunday; Monday had no prompts
    }

    func test6SessionClosesAfter30QuietMinutes() {
        let same = Game.replay(log([.lose, .tell], at: [0, 1799]), now: t0 + 1800)
        XCTAssertEqual(same.fuse, 1.75) // still the Booming Sitting
        XCTAssertTrue(same.boomed)
        XCTAssertEqual(same.sittings.count, 1)
        let next = Game.replay(log([.lose, .tell], at: [0, 1800]), now: t0 + 1801)
        XCTAssertFalse(next.boomed) // it closed: a fresh stick
        XCTAssertEqual(next.burned, 0.36, accuracy: 1e-9)
        XCTAssertEqual(next.sittingStart, t0 + 1800)
        XCTAssertEqual(next.sittings.map(\.isOpen), [false, true])
        let steady = (0..<16).map { Double($0) * 1200 } // a message every 20 minutes for 5 hours: no length cap
        let long = Game.replay(log(steady.map { _ in .none }, at: steady), now: t0 + steady.last! + 1)
        XCTAssertEqual(long.sittings.count, 1)
        XCTAssertEqual(long.sitting?.prompts, 16)
    }

    func test7ClosedByNow() {
        let s = Game.replay(log([.tell]), now: t0 + 31 * 60)
        XCTAssertFalse(s.sittingOpen)
        XCTAssertEqual(s.left, 1)
        XCTAssertTrue(s.currentBurns.isEmpty)
        let b = Game.replay(log([.lose, .lose]), now: t0 + 60 + 31 * 60)
        XCTAssertFalse(b.boomed)
        XCTAssertEqual(Game.stickText(b), "🧨━━━")
        let empty = Game.replay([], now: t0)
        XCTAssertEqual(empty, GameState(fuse: 1, burned: 0, boomed: false, sittingOpen: false, currentBurns: [], booms: []))
    }

    func test8StableBoomIds() {
        let events = log([.lose, .lose, .none, .lose, .lose], at: [0, 1, 2, 5000, 5001]) // the second stick is 1.75 long
        let a = Game.replay(events, now: t0 + 9000), b = Game.replay(Array(events.reversed()), now: t0 + 9000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.booms.map(\.id), [String(Int(t0 * 1000)), String(Int((t0 + 5001) * 1000))])
    }

    func test9BurnsCoolOffAfter30Minutes() {
        // three tells would blow it, but the first has cooled off by the third
        let s = Game.replay(log([.tell, .none, .none, .none, .tell, .none, .none, .none, .tell],
                                at: [0, 500, 1000, 1500, 1700, 1750, 1790, 1795, 1800]), now: t0 + 1801)
        XCTAssertTrue(s.booms.isEmpty)
        XCTAssertEqual(s.currentBurns.count, 2)
        XCTAssertEqual(s.burned, 0.72, accuracy: 1e-9)
    }

    /// Guards docs/why.md#one-boom-per-session.
    func test10BlownUntilTheSessionCloses() {
        let chat = (1...12).map { Double($0) * 300 } // a calm message every 5 minutes for an hour
        let events = log([.lose], at: [0]) + log(chat.map { _ in .none }, at: chat)
        let blown = Game.replay(events, now: t0 + 3700)
        XCTAssertTrue(blown.boomed) // the burn cooled off long ago, but the Sitting isn't over
        XCTAssertEqual(blown.left, 0)
        let fresh = Game.replay(events, now: t0 + 3600 + 1800)
        XCTAssertFalse(fresh.boomed)
        XCTAssertEqual(fresh.left, 1)
        XCTAssertEqual(fresh.fuse, 1.75) // the Boom's growth stays
    }

    func test11TheModelBeatsTheWordList() {
        let calmSwear = Event(ts: t0, burn: .lose, heat: 0.2)
        XCTAssertTrue(Game.replay([calmSwear], now: t0 + 1).booms.isEmpty)
        let quietRage = Event(ts: t0, burn: .none, heat: 1)
        XCTAssertEqual(Game.replay([quietRage], now: t0 + 1).booms.count, 1)
    }

    func test12ARatedMessageWaitsForItsRating() {
        let pending = Event(ts: t0, burn: .lose, rated: true)
        XCTAssertTrue(Game.replay([pending], now: t0 + 10).booms.isEmpty)
        XCTAssertEqual(Game.replay([pending], now: t0 + Game.ratingWait).booms.count, 1) // no rating came: the word list decides
        XCTAssertTrue(pending.awaitingRating(at: t0 + 10))
        XCTAssertFalse(pending.awaitingRating(at: t0 + Game.ratingWait))
        // While it waits it burns and mends nothing at all, so the breeze the app starts the moment the hook hands it
        // over is exactly the look the log brings a second later, and doesn't start again.
        XCTAssertEqual(Game.burn(pending, at: t0 + 10) + Game.mend(pending), 0)
        var rated = pending
        rated.heat = 0.3
        XCTAssertFalse(rated.awaitingRating(at: t0 + 10))
    }

    /// Guards docs/why.md#fresh-start.
    func test13FreshStickOnlyAtSessionClose() {
        let s = Game.replay(log([.lose, .none, .none, .none, .none, .none], at: [0, 300, 600, 900, 1200, 1500]), now: t0 + 1600)
        XCTAssertEqual(s.freshAt, t0 + 1500 + 1800) // 30 quiet minutes after the last message, not after the burn
        XCTAssertNil(Game.replay(log([.tell]), now: t0 + 60).freshAt) // only after a Boom
    }

    /// Guards docs/why.md#cool-mends.
    func testCoolMendsButCantBeBanked() {
        let tell = Event(ts: t0, burn: .tell) // heat 0.6 burns 0.36
        let cool = Event(ts: t0 + 60, burn: .none, heat: 0, cool: 0.6) // mends 0.5 × 0.36
        XCTAssertEqual(Game.replay([tell, cool], now: t0 + 61).burned, 0.18, accuracy: 1e-9)
        let bud = Event(ts: t0 + 60, burn: .none, heat: 0, cool: 1) // mends 0.5, more than is burning
        XCTAssertEqual(Game.replay([tell, bud], now: t0 + 61).burned, 0)
        let early = Event(ts: t0 - 60, burn: .none, heat: 0, cool: 1)
        XCTAssertEqual(Game.replay([early, tell], now: t0 + 1).burned, 0.36, accuracy: 1e-9) // cool can't be banked
        XCTAssertEqual(Game.replay([early, tell], now: t0 + 1).left, Game.full - 0.36, accuracy: 1e-9) // it grew the stick
        let roast = Event(ts: t0, burn: .lose, heat: 1, cool: 1) // hot and cool at once: 1 − 0.5
        XCTAssertEqual(Game.burn(roast, at: t0), 0.5, accuracy: 1e-9)
        XCTAssertTrue(Game.replay([roast], now: t0 + 1).booms.isEmpty) // the same heat alone Booms (test 11)
        XCTAssertEqual(Game.burn(Event(ts: t0, burn: .none, heat: 0.05, cool: 0.05), at: t0), 0) // too faint to count
        XCTAssertEqual(Game.burn(Event(ts: t0, burn: .tell), at: t0), 0.36, accuracy: 1e-9) // no cool is 0
    }

    /// Guards docs/why.md#cool-grows: what's left after each prompt, in made-up sessions.
    func testCoolGrowsTheStick() {
        func left(_ prompts: [(heat: Double, cool: Double)], every gap: Double = 60) -> [Double] {
            var events: [Event] = []
            return prompts.enumerated().map { i, p in
                events.append(Event(ts: t0 + Double(i) * gap, burn: .none, heat: p.heat, cool: p.cool))
                return Game.replay(events, now: events.last!.ts + 1, timeZone: utc).left
            }
        }
        let furious = (heat: 1.0, cool: 0.0), tell = (heat: 0.6, cool: 0.0), calm = (heat: 0.0, cool: 0.0)
        let banter = (heat: 0.0, cool: 0.67), mild = (heat: 0.0, cool: 0.5), bud = (heat: 0.0, cool: 1.0)
        let friendly = (heat: 0.0, cool: 0.4)
        XCTAssertEqual(left([calm, furious]), [1, 0]) // a fresh stick still Booms on one furious prompt
        XCTAssertEqual(left([banter, banter, furious]).last!, 0.2245, accuracy: 1e-3) // banter first: a close shave
        XCTAssertEqual(left(Array(repeating: friendly, count: 6)).last!, 1) // friendly isn't cool: it does nothing
        XCTAssertEqual(left(Array(repeating: mild, count: 3)).last!, 1.1875, accuracy: 1e-9) // just cool: 6.25 % a prompt
        XCTAssertEqual(left(Array(repeating: mild, count: 5)).last!, Game.full) // and no further than full
        XCTAssertEqual(left([bud]), [Game.full]) // one perfect prompt fills it
        XCTAssertEqual(left([tell, tell, tell]).last!, 0) // three tellings-off Boom a fresh stick
        XCTAssertEqual(left([banter, banter, tell, tell, tell]).last!, 0.1445, accuracy: 1e-3) // but not a grown one
        let later = left([banter, banter] + Array(repeating: calm, count: 40) + [furious]).last!
        XCTAssertEqual(later, 0.2245, accuracy: 1e-3) // burns heal and growth stays, 40 minutes on
        XCTAssertEqual(left([bud, calm], every: Game.sittingGap).last!, 1) // until the session closes
    }

    /// Guards docs/why.md#one-boom-per-session.
    func testOneBoomPerSessionEscalatesTiers() {
        let s = Game.replay(log([.lose, .tell, .tell, .tell, .lose, .lose]), now: t0 + 400)
        XCTAssertEqual(s.booms.count, 1)
        XCTAssertEqual(s.booms[0].ts, t0)
        // after the Boom the burn starts again from zero: 0.36 doesn't escalate, 0.72 is half the stick, 1.08 a whole one
        XCTAssertEqual(s.booms[0].escalations, [t0 + 120, t0 + 180])
        XCTAssertEqual(s.booms[0].tier, 3)
        XCTAssertEqual(Game.tiers[s.booms[0].tier - 1].name, "Meltdown")
        XCTAssertEqual(s.sitting?.boom, s.booms[0])
        XCTAssertEqual(s.sitting?.tier, 3) // capped: two more loses change nothing
        XCTAssertEqual(s.fuse, 1.75) // one Boom, one growth
    }

    /// Guards docs/why.md#tiers-flavour-not-volume: each further half of the stick that blew is a tier.
    func testEscalatesEveryHalfStick() {
        let chain = Game.replay(log([.lose, .tell, .tell]), now: t0 + 180)
        XCTAssertEqual(chain.booms.map(\.escalations), [[t0 + 120]]) // 0.72 of a 1.0 stick
        XCTAssertEqual(chain.burned, 0.72, accuracy: 1e-9) // it keeps counting toward Meltdown
        let melt = Game.replay(log([.lose, .lose]), now: t0 + 120)
        XCTAssertEqual(melt.booms.map(\.escalations), [[t0 + 60, t0 + 60]]) // a whole stick at once: two tiers
        // half of the stick that blew (1.75 after an earlier Boom), not of a fresh one
        let long = log([.lose]) + log([.lose, .lose, .tell, .tell, .tell], at: [4000, 4060, 4120, 4180, 4240])
        XCTAssertEqual(Game.replay(long, now: t0 + 4300).booms.map(\.escalations), [[], [t0 + 4240]]) // 1.08 ≥ 0.875
    }

    /// Guards docs/why.md#tiers-flavour-not-volume: only the same outburst escalates, within 30 minutes of the Boom.
    func testEscalatesOnlyWithin30Minutes() {
        let blown = log([.lose, .none, .none], at: [0, 600, 1200])
        let soon = Game.replay(blown + log([.lose], at: [1799]), now: t0 + 1801)
        XCTAssertEqual(soon.booms[0].tier, 3)
        let later = Game.replay(blown + log([.lose], at: [1800]), now: t0 + 1801)
        XCTAssertEqual(later.booms[0].tier, 1)
        XCTAssertTrue(later.boomed) // still blown until the Sitting closes
        let spread = Game.replay(blown + log([.tell, .tell], at: [1500, 1900]), now: t0 + 2000)
        XCTAssertEqual(spread.booms[0].tier, 1) // 0.72 in all, but only 0.36 of it in time
    }

    /// Guards docs/why.md#close-call.
    func testCloseCallOncePerDipNeverOnABoom() {
        let dip = log([.tell, .tell], at: [0, 60]) // 0.28 of the stick left: the last third
        let mend = Event(ts: t0 + 120, burn: .none, heat: 0, cool: 1) // 0.72 − 0.5: back to 0.78 left
        XCTAssertEqual(Game.replay(dip + [mend], now: t0 + 200).closeCalls, [CloseCall(ts: t0 + 60, cooled: t0 + 120)])
        XCTAssertEqual(Game.replay(dip, now: t0 + 100).closeCalls, []) // still in it
        XCTAssertEqual(Game.replay(dip, now: t0 + 1810).closeCalls, [CloseCall(ts: t0 + 60, cooled: t0 + 1800)]) // the first tell cooled off
        XCTAssertEqual(Game.replay(dip, now: t0 + 10_000).sittings[0].closeCalls, [CloseCall(ts: t0 + 60, cooled: t0 + 1800)]) // walked away
        XCTAssertEqual(Game.replay(log([.tell, .tell, .tell], at: [0, 60, 120]), now: t0 + 10_000).closeCalls, []) // it Boomed
        // one per dip: more heat inside the dip adds none, and a second dip is a second close call
        let twice = dip + [Event(ts: t0 + 90, burn: .none, heat: 0.4), mend, Event(ts: t0 + 180, burn: .tell),
                           Event(ts: t0 + 240, burn: .none, heat: 0, cool: 1)]
        XCTAssertEqual(Game.replay(twice, now: t0 + 300).closeCalls,
                       [CloseCall(ts: t0 + 60, cooled: t0 + 120), CloseCall(ts: t0 + 180, cooled: t0 + 240)])
    }

    /// Guards docs/why.md#close-call: a heat-1 burn on a 1.5 stick leaves exactly a third, which floats a hair above it.
    func testCloseCallAtExactlyOneThird() {
        let day = 86_400.0
        XCTAssertGreaterThan(1 - 1.0 / 1.5, Game.closeCallLeft) // the float edge
        XCTAssertTrue(Game.inLastThird(1 - 1.0 / 1.5))
        XCTAssertFalse(Game.inLastThird(0.334))
        // a Boom (1.75), a calm workday (1.5), then a furious prompt on Saturday
        let events = log([.lose, .none, .none], at: [0, day, 2 * day]) + [Event(ts: t0 + 2 * day + 60, burn: .none, heat: 1)]
        let dipped = Game.replay(events, now: t0 + 2 * day + 120, timeZone: utc)
        XCTAssertEqual(dipped.fuse, 1.5)
        XCTAssertEqual(dipped.burned, 1)
        XCTAssertEqual(Game.stickText(dipped), "🧨✨")
        let s = Game.replay(events, now: t0 + 3 * day, timeZone: utc) // walked away: the burn cooled off
        XCTAssertEqual(s.closeCalls, [CloseCall(ts: t0 + 2 * day + 60, cooled: t0 + 2 * day + 60 + 1800)])
    }

    func testSessionSummaries() {
        let calm = (0..<6).map { Event(ts: t0 + Double($0) * 60, burn: .none, heat: 0.1, cool: $0 < 2 ? 0.8 : 0.2) }
        let hot = log([.tell, .lose, .none], at: [4000, 4060, 4120])
        let s = Game.replay(calm + hot, now: t0 + 4200)
        XCTAssertEqual(s.sittings.count, 2)
        let first = s.sittings[0]
        XCTAssertEqual([first.start, first.end], [t0, t0 + 300])
        XCTAssertEqual(first.prompts, 6)
        XCTAssertEqual(first.coolPrompts, 2) // 0.2 is under a half
        XCTAssertEqual(first.peakHeat, 0.1)
        XCTAssertEqual(first.tier, 0)
        XCTAssertNil(first.boom)
        XCTAssertFalse(first.isOpen)
        let second = s.sittings[1]
        XCTAssertEqual([second.start, second.end], [t0 + 4000, t0 + 4120])
        XCTAssertEqual(second.prompts, 3)
        XCTAssertEqual(second.peakHeat, 1)
        XCTAssertEqual(second.tier, 1)
        XCTAssertEqual(second.boom?.ts, t0 + 4060)
        XCTAssertEqual(second.lastBurn, t0 + 4060)
        XCTAssertTrue(second.isOpen)
        XCTAssertEqual(s.sitting, second)
        XCTAssertNil(Game.replay(calm, now: t0 + 10_000).sitting) // all closed
    }

    func testText() {
        var s = Game.replay([], now: t0)
        XCTAssertEqual(Game.stickText(s), "🧨━━━")
        s.boomed = true
        XCTAssertEqual(Game.stickText(s), "💥")
        XCTAssertEqual([0.05, 0.2, 0.5, 0.7, 0.9].map(Game.heatWord), ["cool", "mild", "warm", "hot", "boiling"])
    }
}

final class RestTests: XCTestCase {
    let t0 = 1_792_670_480.0

    func testRestEndsABoomedSittingWithoutShorteningTheFuse() {
        let s = Game.replay([Event(ts: t0, burn: .lose), Event(ts: t0 + 60, burn: .rest)], now: t0 + 61)
        XCTAssertFalse(s.boomed)
        XCTAssertFalse(s.sittingOpen)
        XCTAssertEqual(s.fuse, 1.75) // the Boom's growth stays
        XCTAssertEqual(s.left, 1)
    }

    func testPromptAfterRestStartsFresh() {
        let events = [Event(ts: t0, burn: .lose), Event(ts: t0 + 60, burn: .rest), Event(ts: t0 + 2000, burn: .tell)]
        let s = Game.replay(events, now: t0 + 2001)
        XCTAssertEqual(s.fuse, 1.75)
        XCTAssertEqual(s.burned, 0.36, accuracy: 1e-9)
        XCTAssertTrue(s.sittingOpen)
        XCTAssertEqual(s.sittings.count, 2)
    }

    func testRestOnACalmSittingClosesLikeABreak() {
        let events = [Event(ts: t0, burn: .lose), Event(ts: t0 + 2000, burn: .tell)]
        let rested = Game.replay(events + [Event(ts: t0 + 2060, burn: .rest)], now: t0 + 2061)
        let walked = Game.replay(events, now: t0 + 2000 + 1800)
        XCTAssertEqual(rested.fuse, 1.75) // a calm Sitting doesn't shorten it; a calm workday does
        XCTAssertEqual(rested.fuse, walked.fuse)
        XCTAssertEqual(rested.sittings.map(\.isOpen), walked.sittings.map(\.isOpen))
    }

    /// Guards docs/why.md#rare-booms: a rest isn't a prompt, so a day with only a rest in it isn't a calm workday.
    func testARestIsntAWorkday() {
        let day = 86_400.0, utc = TimeZone(identifier: "UTC")!
        let boom = [Event(ts: t0, burn: .lose)] // Thursday Booms: 1.75
        XCTAssertEqual(Game.replay(boom + [Event(ts: t0 + day, burn: .rest)], now: t0 + 3 * day, timeZone: utc).fuse, 1.75)
        XCTAssertEqual(Game.replay(boom + [Event(ts: t0 + day, burn: .none)], now: t0 + 3 * day, timeZone: utc).fuse, 1.5) // a prompt makes Friday one
    }

    /// Guards docs/why.md#close-call: a dip that a rest cuts short never climbed back out, so it's no close call.
    func testADipCutShortByARestIsNoCloseCall() {
        let dip = [Event(ts: t0, burn: .tell), Event(ts: t0 + 60, burn: .tell)] // 0.28 of the stick left: the last third
        let rested = Game.replay(dip + [Event(ts: t0 + 120, burn: .rest)], now: t0 + 10_000)
        XCTAssertEqual(rested.closeCalls, [])
        XCTAssertEqual(rested.sittings.map(\.aura), [0])
        XCTAssertEqual(Game.replay(dip, now: t0 + 10_000).closeCalls.count, 1) // walked away instead: a close call
    }
}

final class VibeTests: XCTestCase {
    let t0 = 1_792_670_480.0

    func testFirstMatchWins() {
        func vibe(_ events: [Event], hour: Bool = false) -> String {
            Vibe.of(Game.replay(events, now: t0 + 100), recent: events, boomedWithinHour: hour, now: t0 + 100).label
        }
        XCTAssertEqual(vibe([Event(ts: t0, burn: .lose)]), "Rather explosive")
        XCTAssertEqual(vibe([Event(ts: t0, burn: .tell), Event(ts: t0 + 1, burn: .tell)]), "Running rather hot") // 0.28 left
        XCTAssertEqual(vibe([Event(ts: t0, burn: .tell), Event(ts: t0 + 1, burn: .none, heat: 0.75)]), "Barely contained") // 0.08 left
        XCTAssertEqual(vibe([Event(ts: t0, burn: .tell)]), "Mildly offended")
        XCTAssertEqual(vibe([Event(ts: t0, burn: .none, heat: 0.4)]), "A little prickly")
        XCTAssertEqual(vibe([Event(ts: t0, burn: .none)], hour: true), "Remarkably recovered")
        XCTAssertEqual(vibe([Event(ts: t0, burn: .none, mood: "hyped"), Event(ts: t0 + 1, burn: .none, mood: "grateful")]), "Dangerously enthusiastic")
        XCTAssertEqual(vibe((0..<30).map { Event(ts: t0 + Double($0), burn: .none) }), "Suspiciously calm")
        XCTAssertEqual(vibe([Event(ts: t0, burn: .none)]), "Perfectly civil")
    }

    func testBandsCandidatesAndSummary() {
        let now = t0 + 100
        let calm = (0..<6).map { Event(ts: t0 + Double($0), burn: .none, heat: 0.05, mood: "neutral") }
        XCTAssertEqual(Vibe.band(Game.replay(calm, now: now), recent: calm, now: now), .calm)
        let warm = calm + [Event(ts: t0 + 10, burn: .none, heat: 0.4, mood: "frustrated")]
        XCTAssertEqual(Vibe.band(Game.replay(warm, now: now), recent: warm, now: now), .warm)
        let blown = [Event(ts: t0, burn: .lose)]
        XCTAssertEqual(Vibe.band(Game.replay(blown, now: now), recent: blown, now: now), .explosive)

        let mine = (0..<5).map { Vibe("🧯", "Mine \($0)", .calm, when: "w", story: "s") } + [Vibe("🔥", "Hot one", .hot, when: "w", story: "s")]
        let picks = Vibe.candidates(.calm, personal: mine, seed: 7)
        XCTAssertEqual(picks.count, 6)
        XCTAssertEqual(picks.prefix(3).map(\.label).allSatisfy { $0.hasPrefix("Mine") }, true) // yours first, at most three
        XCTAssertTrue(picks.allSatisfy { $0.band == .calm })
        XCTAssertEqual(Vibe.candidates(.calm, personal: mine, seed: 7), picks) // same moment, same shortlist
        XCTAssertNotEqual(Vibe.candidates(.calm, personal: mine, seed: 8), picks)
        XCTAssertEqual(Vibe.candidates(.explosive, personal: [], seed: 3).count, 2)

        let summary = Vibe.summary(Game.replay(warm, now: now), recent: warm, now: now)
        XCTAssertTrue(summary.hasPrefix("7 messages in 30 minutes"))
        XCTAssertTrue(summary.contains("moods: neutral 6, frustrated 1"))
        XCTAssertTrue(summary.contains("% left"))
    }

    func testTopicVibesOnlyShowWhenTheSessionIsAboutThem() {
        let design = (0..<5).map { Event(ts: t0 + Double($0), burn: .none, heat: 0.05, mood: "neutral", topic: $0 < 3 ? "design" : "code") }
        XCTAssertEqual(Vibe.topic(design), "design")
        XCTAssertNil(Vibe.topic(Array(design.prefix(2)))) // two isn't enough
        XCTAssertNil(Vibe.topic(design.map { var e = $0; e.topic = "other"; return e }))
        var pixels = Vibe("🖌️", "Pixel fussing", .calm, when: "small design notes", story: "s")
        pixels.topic = "design"
        let general = Vibe("🌙", "Past bedtime", .calm, when: "late", story: "s")
        XCTAssertEqual(Vibe.candidates(.calm, personal: [pixels, general], seed: 0, topic: "design").first?.label, "Pixel fussing")
        XCTAssertFalse(Vibe.candidates(.calm, personal: [pixels, general], seed: 0, topic: "code").contains { $0.label == "Pixel fussing" })
        XCTAssertFalse(Vibe.candidates(.calm, personal: [pixels, general], seed: 0).contains { $0.label == "Pixel fussing" })
        XCTAssertTrue(Vibe.summary(Game.replay(design, now: t0 + 100), recent: design, now: t0 + 100).contains("topics: design 3, code 2"))
    }

    func testPersonalVibesFile() throws {
        let json = #"{"lunte":"fuse-vibes","v":1,"made":"2026-10-23","vibes":[{"emoji":"🧯","label":"Migration grief","band":"hot","when":"the database keeps breaking","story":"It began as a rename."}]}"#
        let file = try JSONDecoder().decode(FuseVibes.self, from: Data(json.utf8))
        XCTAssertEqual(file.vibes[0].band, .hot)
        XCTAssertEqual(file.problems, ["no vibes for: calm, warm, explosive"])
    }
}
