import XCTest
@testable import LunteCore

/// What the popover shows on hover: the signals behind a Burn, and the prompt read back from Claude's transcript.
final class DisplayTests: XCTestCase {
    func testSignals() {
        XCTAssertEqual(Classifier.signals("I SAID DONT TOUCH IT"), ["CAPS", "told off: i said"])
        XCTAssertEqual(Classifier.signals("fucking awesome!!"), ["swear, but happy", "!!, but happy", "happy: awesome"])
        XCTAssertEqual(Classifier.signals("rename foo to bar"), [])
        XCTAssertEqual(Classifier.signals("this is a test 3 2 1 pow"), ["the onboarding phrase"])
    }

    func testTranscriptPrompt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lunte-tx-\(UUID().uuidString)")
        let project = root.appendingPathComponent("-Users-someone-project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [
            #"{"type":"user","timestamp":"2026-10-22T14:40:00.000Z","message":{"content":"why did you delete my tests"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-22T14:40:01.000Z","message":{"content":"Sorry"}}"#,
            #"{"type":"user","timestamp":"2026-10-22T14:41:00.500Z","message":{"content":[{"type":"text","text":"wtf"}]}}"#,
            #"{"type":"user","timestamp":"2026-10-22T14:50:00.000Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"user","isMeta":true,"timestamp":"2026-10-22T14:50:30.000Z","message":{"content":"system note"}}"#,
            #"{"type":"user","timestamp":"2026-10-22T14:52:00.000Z","message":{"content":"sent while you were busy"}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: project.appendingPathComponent("s1.jsonl"))
        let at = { (s: String) in ISO8601DateFormatter().date(from: s)!.timeIntervalSince1970 }
        XCTAssertEqual(Transcript.prompt(sid: "s1", ts: at("2026-10-22T14:40:01Z"), root: root), "why did you delete my tests")
        XCTAssertEqual(Transcript.prompt(sid: "s1", ts: at("2026-10-22T14:41:01Z"), root: root), "wtf")
        XCTAssertEqual(Transcript.prompt(sid: "s1", ts: at("2026-10-22T14:50:00Z"), root: root), "sent while you were busy") // queued
        XCTAssertNil(Transcript.prompt(sid: "s1", ts: at("2026-10-22T15:30:00Z"), root: root)) // nothing close or after
        XCTAssertNil(Transcript.prompt(sid: "nope", ts: at("2026-10-22T14:40:00Z"), root: root))
        XCTAssertNil(Transcript.prompt(sid: "../s1", ts: at("2026-10-22T14:40:00Z"), root: root))
        // A resumed chat copies its history into a new file; each prompt still counts once.
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: project.appendingPathComponent("s2.jsonl"))
        XCTAssertEqual(Transcript.all(since: 0, root: root).map(\.text), ["why did you delete my tests", "wtf", "sent while you were busy"])
    }
}
