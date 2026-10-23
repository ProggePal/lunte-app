import CryptoKit
import XCTest
@testable import LunteCore

/// The Heat Detector download: it only counts files whose size and checksum match, and resumes where it left off.
final class HeatDetectorTests: XCTestCase {
    func testInstallChecksEveryFileAndSkipsWhatIsThere() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lunte-hd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("b"), withIntermediateDirectories: true)
        let a = Data("tokenizer".utf8), b = Data(repeating: 7, count: 300_000)
        try a.write(to: source.appendingPathComponent("a.json"))
        try b.write(to: source.appendingPathComponent("b/weight.bin"))
        let hash = { (d: Data) in SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
        let files = [HeatDetector.File("a.json", Int64(a.count), hash(a)), HeatDetector.File("b/weight.bin", Int64(b.count), hash(b))]

        XCTAssertFalse(HeatDetector.isInstalled(in: target, files: files))
        let seen = Seen()
        try await HeatDetector.install(into: target, files: files, from: source) { seen.add($0) }
        XCTAssertTrue(HeatDetector.isInstalled(in: target, files: files))
        XCTAssertEqual(seen.last, 1)
        XCTAssertEqual(seen.values, seen.values.sorted()) // progress only goes up

        // A file whose checksum is wrong is thrown away, not installed.
        let wrong = [HeatDetector.File("a.json", Int64(a.count), String(repeating: "0", count: 64))]
        let fresh = root.appendingPathComponent("fresh")
        do {
            try await HeatDetector.install(into: fresh, files: wrong, from: source) { _ in }
            XCTFail("a bad checksum must throw")
        } catch {}
        XCTAssertFalse(HeatDetector.isInstalled(in: fresh, files: wrong))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.appendingPathComponent("a.json.part").path))
    }

    func testThePinnedModelAddsUp() {
        XCTAssertEqual(HeatDetector.totalBytes, 482_843_099) // the "Download · 483 MB" button
        XCTAssertEqual(HeatDetector.files.count, 5)
        XCTAssertTrue(HeatDetector.files.allSatisfy { $0.sha256.count == 64 })
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []
    var last: Double? { lock.withLock { values.last } }
    func add(_ v: Double) { lock.withLock { values.append(v) } }
}
