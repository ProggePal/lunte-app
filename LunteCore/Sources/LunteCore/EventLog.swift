// events.jsonl (contract §1): one JSON Event per line, appended with a single write() under O_APPEND.
import Foundation

public enum EventLog {
    /// ~/Library/Application Support/Lunte/events.jsonl, or $LUNTE_LOG when set (tests, development)
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["LUNTE_LOG"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lunte/events.jsonl")
    }

    public static func append(_ event: Event, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let line = try encoder.encode(event) + Data("\n".utf8)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Skips unparseable lines and impossible timestamps (one would crash Boom ids); sorted by ts.
    /// Heat lines (heat and cool) are merged into the prompt with the same ts and dropped; one without its prompt is
    /// dropped too.
    public static func read(_ url: URL = defaultURL) -> [Event] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let all = data.split(separator: UInt8(ascii: "\n"))
            .compactMap { try? decoder.decode(Event.self, from: Data($0)) }
            .filter { $0.ts.isFinite && $0.ts > 0 && $0.ts < 1e11 }
        let ratings = Dictionary(all.filter { $0.burn == .heat }.map { ($0.ts, $0) }) { $1 }
        return all.filter { $0.burn != .heat }
            .map { e in
                guard let r = ratings[e.ts] else { return e }
                var e = e
                e.heat = r.heat.map { min(1, max(0, $0)) }
                e.cool = r.cool.map { min(1, max(0, $0)) }
                e.mood = r.mood
                e.topic = r.topic
                return e
            }
            .sorted { $0.ts < $1.ts }
    }
}
