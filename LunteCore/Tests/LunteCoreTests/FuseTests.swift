import XCTest
@testable import LunteCore

/// The personal fuse: candidates for your AI to rate, the labels it writes, and the model Lunte trains on them.
final class FuseTests: XCTestCase {
    func testTrainingLearnsARealSignalAndReportsAnHonestFit() throws {
        // 150 messages with 5 features; the rating depends on feature 0 (up) and 1 (down), the rest is noise.
        var rng = SystemRandomNumberGenerator(), x: [[Double]] = [], y: [Int] = []
        for _ in 0..<150 {
            let f = (0..<5).map { _ in Double.random(in: -1...1, using: &rng) }
            x.append(f)
            y.append(Int(max(0, min(3, (1.5 + 1.6 * f[0] - 0.8 * f[1] + Double.random(in: -0.5...0.5, using: &rng)).rounded()))))
        }
        let fuse = PersonalFuse.train(features: x, ratings: y, probes: ["a", "b", "c", "d", "e"], rater: "test", made: "2026-10-23")
        XCTAssertGreaterThan(try XCTUnwrap(fuse.fit), 0.85) // judged on held-out folds
        XCTAssertGreaterThan(fuse.weights[0], 0)
        XCTAssertLessThan(fuse.weights[1], 0)
        XCTAssertGreaterThan(fuse.heat([1, -1, 0, 0, 0]), fuse.heat([-1, 1, 0, 0, 0]))
        XCTAssertEqual(fuse.heat([9, -9, 0, 0, 0]), 1) // clamped to 0...1
        XCTAssertEqual(fuse.heat([-9, 9, 0, 0, 0]), 0)
        // Your range: as many training messages reach heat 1 as your AI rated furious, give or take ties.
        let furious = y.filter { $0 == 3 }.count, boiling = x.filter { fuse.heat($0) >= 0.999 }.count
        XCTAssertEqual(Double(boiling), Double(furious), accuracy: max(2, Double(furious) * 0.2))
        XCTAssertEqual(fuse.cuts.compactMap { $0 }, fuse.cuts.compactMap { $0 }.sorted())
        let back = try JSONDecoder().decode(PersonalFuse.self, from: JSONEncoder().encode(fuse))
        XCTAssertEqual(back, fuse)
    }

    func testALevelYouNeverReachedCapsTheHeat() {
        let x = (0..<60).map { [Double($0)] }, y = (0..<60).map { $0 < 40 ? 0 : 1 } // nobody angry or furious
        let fuse = PersonalFuse.train(features: x, ratings: y, probes: ["a"], rater: nil, made: "")
        XCTAssertNil(fuse.cuts[1])
        XCTAssertEqual(fuse.heat([1000]), 1.0 / 3, accuracy: 1e-9) // irritated at most
        let back = try? JSONDecoder().decode(PersonalFuse.self, from: JSONEncoder().encode(fuse)) // nil cuts survive JSON
        XCTAssertEqual(back, fuse)
    }

    func testNoiseGetsNoFit() throws {
        var x: [[Double]] = [], y: [Int] = []
        for i in 0..<100 { x.append([Double(i % 7), Double(i % 3)]); y.append(i % 4 == 0 ? 2 : 0) }
        let fuse = PersonalFuse.train(features: x, ratings: y, probes: ["a", "b"], rater: nil, made: "")
        XCTAssertLessThan(try XCTUnwrap(fuse.fit), 0.75)
    }

    func testLabelsAndTheirProblems() throws {
        let json = #"{"lunte":"fuse-labels","v":1,"rater":"claude","made":"2026-10-23","labels":[{"sid":"s1","ts":1792744463.009,"rating":3}]}"#
        let labels = try JSONDecoder().decode(FuseLabels.self, from: Data(json.utf8))
        XCTAssertEqual(labels.labels[0], FuseLabels.Label(sid: "s1", ts: 1792744463.009, rating: 3))
        XCTAssertEqual(labels.problems, ["only 1 ratings; rate at least 30, ideally all of them"])
        var bad = labels
        bad.labels = (0..<40).map { FuseLabels.Label(sid: "s", ts: Double($0), rating: $0 == 0 ? 7 : 1) }
        bad.lunte = "x"
        XCTAssertEqual(bad.problems, [#""lunte" must be "fuse-labels""#, "1 ratings are outside 0–3"])
    }

    /// The vibe chip: one in twenty angry-or-worse is hot, one in twenty buddy-or-better is cool.
    func testTheChipIsTheSameMathForEveryone() {
        func chip(hot: Int, cool: Int, of n: Int = 100, coolRated: Bool = true) -> String? {
            let labels = (0..<n).map { i in FuseLabels.Label(sid: "s", ts: Double(i), rating: i < hot ? 2 : 0, cool: coolRated ? (i >= n - cool ? 2 : 0) : nil) }
            return FuseLabels(lunte: "fuse-labels", v: 1, labels: labels).chip?.name
        }
        XCTAssertEqual(chip(hot: 11, cool: 7), "The Roaster") // Paal's setup
        XCTAssertEqual(chip(hot: 5, cool: 4), "Short Fuse")
        XCTAssertEqual(chip(hot: 1, cool: 9), "Best Bud")
        XCTAssertEqual(chip(hot: 4, cool: 4), "Ice Cold")
        XCTAssertNil(chip(hot: 5, cool: 5, of: 20)) // too few ratings to say
        XCTAssertNil(chip(hot: 11, cool: 0, coolRated: false)) // rated before cool: no chip rather than a wrong one
    }

    /// vibes.json v 2 holds session names: the bands are calm, cool, hot and explosive. A v 1 file still checks out.
    func testSessionNamesNeedEveryBand() {
        let name = { (band: Vibe.Band) in Vibe("🚀", "Mad push to prod", band, when: "w", story: "s") }
        let v2 = FuseVibes(lunte: "fuse-vibes", v: 2, made: nil, vibes: [.calm, .cool, .hot, .explosive].map(name))
        XCTAssertEqual(v2.problems, [])
        XCTAssertEqual(FuseVibes(lunte: "fuse-vibes", v: 2, made: nil, vibes: [.calm, .hot, .explosive].map(name)).problems, ["no vibes for: cool"])
        XCTAssertEqual(FuseVibes(lunte: "fuse-vibes", v: 1, made: nil, vibes: [.calm, .warm, .hot, .explosive].map(name)).problems, [])
        XCTAssertTrue(Fuse.setupText.contains(#""v": 2"#)) // setup asks for session names
        XCTAssertFalse(Fuse.setupText.contains("pet peeves")) // names are a pat on the back, never a verdict
    }

    func testLabelsWithAndWithoutCool() throws {
        let old = #"{"lunte":"fuse-labels","v":1,"labels":[{"sid":"s1","ts":1792744463.009,"rating":2}]}"#
        let before = try JSONDecoder().decode(FuseLabels.self, from: Data(old.utf8)) // a file from before cool
        XCTAssertNil(before.labels[0].cool)
        XCTAssertEqual(before.missingCool, 1)
        var heatOnly = before
        heatOnly.labels = (0..<40).map { FuseLabels.Label(sid: "s", ts: Double($0), rating: $0 % 4) }
        XCTAssertEqual(heatOnly.problems, []) // still tunes heat; check-fuse asks for the cool
        var both = heatOnly
        both.labels = (0..<40).map { FuseLabels.Label(sid: "s", ts: Double($0), rating: 0, cool: $0 == 0 ? 4 : $0 % 4) }
        XCTAssertEqual(both.problems, ["1 cool ratings are outside 0–3"])
        XCTAssertEqual(both.missingCool, 0)
        XCTAssertEqual(try JSONDecoder().decode(FuseLabels.self, from: JSONEncoder().encode(both)), both)
        XCTAssertTrue(Fuse.setupText.contains(#""rating": 3, "cool": 0"#)) // the AI is asked for both
    }

    func testCandidatesMixTemperBanterAndCalm() {
        let text = { (i: Int) -> String in i % 50 == 0 ? "why did you do that" : i % 40 == 1 ? "nice one bro" : "rename foo to bar" }
        let all = (0..<1000).map { Transcript.Message(sid: "s", ts: Double($0), text: text($0)) }
        let picked = Fuse.candidates(all, count: 300)
        XCTAssertEqual(picked.count, 300)
        XCTAssertEqual(picked.filter { $0.text.hasPrefix("why") }.count, 20) // every flagged one
        XCTAssertEqual(picked.filter { $0.text.hasPrefix("nice") }.count, 25) // and every one that looks like banter
        XCTAssertEqual(picked.map(\.ts), picked.map(\.ts).sorted())
        XCTAssertEqual(Fuse.candidates(Array(all.prefix(10))).count, 10)
        XCTAssertFalse(Fuse.setupPrompt.contains("pow")) // pasting the prompt must never Boom
        XCTAssertEqual(Classifier.classify(Fuse.setupPrompt), .none) // and doesn't burn either
    }
}
