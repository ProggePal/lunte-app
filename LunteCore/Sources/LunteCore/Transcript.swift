// The prompt behind an event, read from Claude Code's own transcript. Display only, never stored (ADR 0001).
import Foundation

public enum Transcript {
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// The human prompt in session `sid` closest to `ts` (within 5 s), or nil (unknown session, or Claude Code cleaned it up).
    /// A message sent while Claude is busy is recorded only when it's delivered, so without a close match this takes
    /// the first prompt recorded up to 10 minutes after `ts`.
    public static func prompt(sid: String, ts: Double, root: URL = root) -> String? {
        guard !sid.isEmpty, !sid.contains("/"),
              let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for dir in dirs {
            // ponytail: reads the whole session file; the app caches the answer per event
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(sid + ".jsonl")) else { continue }
            var prompts: [(ts: Double, text: String)] = []
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let d = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      d["type"] as? String == "user", d["isMeta"] as? Bool != true,
                      let stamp = (d["timestamp"] as? String).flatMap(iso.date(from:)),
                      let message = d["message"] as? [String: Any] else { continue }
                let content = message["content"]
                let text = (content as? String)
                    ?? (content as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ")
                if let text, !text.isEmpty { prompts.append((stamp.timeIntervalSince1970, text)) } // tool results have no text
            }
            if let close = prompts.filter({ abs($0.ts - ts) < 5 }).min(by: { abs($0.ts - ts) < abs($1.ts - ts) }) { return close.text }
            return prompts.filter { $0.ts >= ts && $0.ts - ts < 600 }.min { $0.ts < $1.ts }?.text
        }
        return nil
    }
}
