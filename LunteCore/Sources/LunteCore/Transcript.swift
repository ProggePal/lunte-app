// Your prompts, read from Claude Code's own transcripts. Display and fuse setup only, never stored (ADR 0001).
import Foundation

public enum Transcript {
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// One prompt you typed: its session, when, and the text.
    public struct Message: Equatable, Sendable {
        public var sid: String
        public var ts: Double
        public var text: String
    }

    /// The human prompt in session `sid` closest to `ts` (within 5 s), or nil (unknown session, or Claude Code cleaned it up).
    /// A message sent while Claude is busy is recorded only when it's delivered, so without a close match this takes
    /// the first prompt recorded up to 10 minutes after `ts`.
    public static func prompt(sid: String, ts: Double, root: URL = root) -> String? {
        guard !sid.isEmpty, !sid.contains("/"),
              let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            // ponytail: reads the whole session file; the app caches the answer per event
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(sid + ".jsonl")) else { continue }
            let prompts = parse(data, human: false)
            if let close = prompts.filter({ abs($0.ts - ts) < 5 }).min(by: { abs($0.ts - ts) < abs($1.ts - ts) }) { return close.text }
            return prompts.filter { $0.ts >= ts && $0.ts - ts < 600 }.min { $0.ts < $1.ts }?.text
        }
        return nil
    }

    /// Everything you typed since `since`, oldest first: machine messages, tool results, slash commands and
    /// interruptions left out, and agent or system blocks cut from what's left (`Classifier.human`).
    public static func all(since: Double, root: URL = root) -> [Message] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [Message] = []
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard (changed?.timeIntervalSince1970 ?? 0) >= since, // a session untouched since then holds nothing newer
                      let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
                let sid = file.deletingPathExtension().lastPathComponent
                out += parse(data, human: true).filter { $0.ts >= since }.map { Message(sid: sid, ts: $0.ts, text: $0.text) }
            }
        }
        // A resumed or forked chat copies its history into a new file: the same prompt, at the same time, counts once.
        var seen = Set<String>()
        return out.sorted { $0.ts < $1.ts }.filter { seen.insert("\($0.ts) \($0.text)").inserted }
    }

    private static func parse(_ data: Data, human: Bool) -> [(ts: Double, text: String)] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let userType = Data(#""type":"user""#.utf8), toolResult = Data(#""tool_use_id""#.utf8)
        var prompts: [(ts: Double, text: String)] = []
        // Only your own lines get parsed: tool results are logged as user lines too, and they're most of the bytes.
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: userType) != nil && line.range(of: toolResult) == nil {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  d["type"] as? String == "user", d["isMeta"] as? Bool != true,
                  let stamp = (d["timestamp"] as? String).flatMap(iso.date(from:)),
                  let message = d["message"] as? [String: Any] else { continue }
            let content = message["content"]
            guard var text = (content as? String)
                ?? (content as? [[String: Any]])?.compactMap({ $0["text"] as? String }).joined(separator: " ") else { continue }
            if human {
                if d["isSidechain"] as? Bool == true || d["isCompactSummary"] as? Bool == true { continue }
                if let origin = d["origin"] as? [String: Any], origin["kind"] as? String != "human" { continue }
                text = Classifier.human(text)
                if ["[Request interrupted", "<command-", "<local-command", "<bash-", "Caveat:", "This session is being continued"]
                    .contains(where: text.hasPrefix) { continue }
            }
            if !text.isEmpty { prompts.append((stamp.timeIntervalSince1970, text)) } // tool results have no text
        }
        return prompts
    }
}
