import XCTest
@testable import LunteCore

/// The first Boom is the onboarding test, and the review's crash-loop fix.
final class OnboardingTests: XCTestCase {
    func testPhrase() {
        for prompt in ["3 2 1 boom", "3, 2, 1… BOOM!", "this is a test 3 2 1 pow", "This is a test 3, 2, 1… POW!", "321 pow", "ok 3-2-1 pow wtf"] {
            XCTAssertEqual(Classifier.classify(prompt), .test, prompt)
        }
        for prompt in ["13 2 1 pow", "3 2 1 power up", "pow 3 2 1", "3 2 1 boomer"] {
            XCTAssertNotEqual(Classifier.classify(prompt), .test, prompt)
        }
    }

    func testTestNeverBurnsButKeepsTheSittingOpen() {
        let t0 = 1_792_670_480.0
        let s = Game.replay([Event(ts: t0, burn: .test), Event(ts: t0 + 1700, burn: .lose)], now: t0 + 1701)
        XCTAssertEqual(s.booms.count, 1)
        XCTAssertEqual(s.booms[0].litBy.map(\.burn), [.lose])
        let quiet = Game.replay([Event(ts: t0, burn: .test)], now: t0 + 60)
        XCTAssertEqual(quiet.left, 1)
        XCTAssertTrue(quiet.sittingOpen)
    }

    func testImpossibleTimestampsAreDropped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lunte-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
        {"v":1,"ts":1e300,"burn":"lose","sid":""}
        {"v":1,"ts":-5,"burn":"lose","sid":""}
        {"v":1,"ts":1792670480,"burn":"lose","sid":""}

        """.utf8).write(to: url)
        let events = EventLog.read(url)
        XCTAssertEqual(events.map(\.ts), [1792670480])
        XCTAssertEqual(Game.replay(events, now: 1792670490).booms.count, 1) // and replay doesn't trap
    }
}
