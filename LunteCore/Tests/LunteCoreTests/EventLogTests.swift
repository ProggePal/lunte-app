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
    }
}
