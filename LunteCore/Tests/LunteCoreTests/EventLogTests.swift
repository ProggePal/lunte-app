import XCTest
@testable import LunteCore

final class EventLogTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lunte-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTripSkipsCorruptLines() throws {
        let url = dir.appendingPathComponent("nested/events.jsonl") // directory doesn't exist yet
        let late = Event(ts: 1_792_670_490.5, burn: .lose, sid: "s\"1")
        let early = Event(ts: 1_792_670_480.123, burn: .tell)
        func junk(_ s: String) throws {
            let h = try FileHandle(forWritingTo: url)
            h.seekToEndOfFile()
            h.write(Data(s.utf8))
            h.closeFile()
        }
        try EventLog.append(late, to: url)
        try junk("not json\n{\"v\":1,\"ts\":3,\"burn\":\"meh\",\"sid\":\"\"}\n")
        try EventLog.append(early, to: url)
        try junk("{\"v\":1,\"ts\":") // truncated last line
        XCTAssertEqual(EventLog.read(url), [early, late])

        let first = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")[0]
        let keys = try JSONSerialization.jsonObject(with: Data(first.utf8)) as! [String: Any]
        XCTAssertEqual(Set(keys.keys), ["v", "ts", "burn", "sid"])
    }

    func testHeatLinesMergeIntoTheirPrompt() throws {
        let url = dir.appendingPathComponent("heat.jsonl")
        let ts = 1_792_670_480.123456789
        try EventLog.append(Event(ts: ts, burn: .lose, sid: "s1", rated: true), to: url)
        try EventLog.append(Event(ts: ts + 5, burn: .none), to: url)
        try EventLog.append(Event(ts: ts, burn: .heat, heat: 1.7, mood: "frustrated"), to: url)
        try EventLog.append(Event(ts: ts + 99, burn: .heat, heat: 0.5), to: url) // its prompt never got logged
        let events = EventLog.read(url)
        XCTAssertEqual(events.map(\.ts), [ts, ts + 5])
        XCTAssertEqual(events[0].heat, 1) // clamped to 0...1
        XCTAssertEqual(events[0].mood, "frustrated")
        XCTAssertNil(events[1].heat)
    }

    func testCoolMergesAndOldLinesStillRead() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cool.jsonl"), ts = 1_792_670_480.5
        try Data("""
        {"v":1,"ts":\(ts),"burn":"none","sid":"s","rated":true}
        {"v":1,"ts":\(ts),"burn":"heat","sid":"","heat":0.1,"mood":"hyped"}
        {"v":1,"ts":\(ts + 1),"burn":"none","sid":"s","rated":true}

        """.utf8).write(to: url)
        try EventLog.append(Event(ts: ts + 1, burn: .heat, heat: 0.2, cool: 1.4), to: url)
        let events = EventLog.read(url)
        XCTAssertEqual(events[0].heat, 0.1)
        XCTAssertNil(events[0].cool) // a heat line from before cool
        XCTAssertEqual(events[1].heat, 0.2)
        XCTAssertEqual(events[1].cool, 1) // clamped to 0...1
    }

    func testMissingFileReadsEmpty() {
        XCTAssertEqual(EventLog.read(dir.appendingPathComponent("nope.jsonl")), [])
    }

    /// Runs the built hook with LUNTE_LOG in a temp dir: one valid line, nothing printed, exit 0 on every path.
    func testHookBinary() throws {
        let hook = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("lunte-hook")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hook.path), "build lunte-hook first")
        let log = dir.appendingPathComponent("hook/events.jsonl")

        func run(_ input: String, log: URL) throws -> (Int32, Data) {
            let p = Process(), stdin = Pipe(), out = Pipe()
            p.executableURL = hook
            p.environment = ProcessInfo.processInfo.environment.merging(["LUNTE_LOG": log.path]) { $1 }
            p.standardInput = stdin
            p.standardOutput = out
            p.standardError = out
            try p.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
            p.waitUntilExit()
            return (p.terminationStatus, out.fileHandleForReading.readDataToEndOfFile())
        }

        let (status, output) = try run(#"{"prompt":"wtf","session_id":"s1","cwd":"/x"}"#, log: log)
        XCTAssertEqual(status, 0)
        XCTAssertEqual(output, Data())
        for (input, path) in [("not json", log), ("", log), (#"{"prompt":"wtf"}"#, URL(fileURLWithPath: "/dev/null/no/events.jsonl"))] {
            let (status, output) = try run(input, log: path)
            XCTAssertEqual(status, 0, input)
            XCTAssertEqual(output, Data(), input)
        }

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let event = try JSONDecoder().decode(Event.self, from: Data(lines[0].utf8))
        XCTAssertEqual(event.burn, .lose)
        XCTAssertEqual(event.sid, "s1")
        XCTAssertEqual(event.ts, Date().timeIntervalSince1970, accuracy: 60)
        XCTAssertNil(event.rated) // nobody listening

        // With the app listening, the hook hands it the text, and the ts survives the trip exactly.
        let short = URL(fileURLWithPath: "/tmp/lunte-\(UUID().uuidString.prefix(8))") // socket paths max out at 104 bytes
        defer { try? FileManager.default.removeItem(at: short) }
        try FileManager.default.createDirectory(at: short, withIntermediateDirectories: true)
        let rlog = short.appendingPathComponent("events.jsonl")
        let server = ScorerSocket.listen(at: short.appendingPathComponent("scorer.sock"))
        XCTAssertGreaterThanOrEqual(server, 0)
        defer { close(server) }
        let (s2, o2) = try run(#"{"prompt":"<system-reminder>x</system-reminder>why did you\n```\ncode\n```","session_id":"s2"}"#, log: rlog)
        XCTAssertEqual(s2, 0)
        XCTAssertEqual(o2, Data())
        let conn = accept(server, nil, nil)
        XCTAssertGreaterThanOrEqual(conn, 0)
        defer { close(conn) }
        let got = FileHandle(fileDescriptor: conn).readDataToEndOfFile()
        let sent = try JSONSerialization.jsonObject(with: got) as! [String: Any]
        let logged = EventLog.read(rlog)[0]
        XCTAssertEqual(sent["ts"] as? Double, logged.ts)
        XCTAssertEqual(sent["text"] as? String, "why did you\n```\ncode\n```") // what you typed, reminder cut out
        XCTAssertEqual(logged.rated, true)
        XCTAssertEqual(logged.burn, .tell)
    }
}
