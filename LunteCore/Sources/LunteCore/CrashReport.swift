// Lunte's own crash reports, as macOS writes them, cut down to what finds the bug: versions and function names, never
// free text, so never a prompt, path or name.
import Foundation

public enum CrashReport {
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    /// Lunte's reports in `folder` written after `since`, oldest first.
    public static func since(_ since: Date, in folder: URL = folder) -> [(url: URL, at: Date)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("Lunte-") && $0.pathExtension == "ips" }
            .compactMap { url in (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (url, $0) } }
            .filter { $0.at > since }
            .sorted { $0.at < $1.at }
    }

    /// An `.ips` report as a few lines of text: the version and macOS, the exception, and the crashed thread's frames,
    /// as functions only. Its message is left out: free text, which a framework can fill with what it was handed.
    public static func summary(_ ips: String, home: String = NSHomeDirectory()) -> String? {
        let parts = ips.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2,
              let head = try? JSONSerialization.jsonObject(with: Data(parts[0].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any] else { return nil }
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        func frames(_ list: Any?) -> [String] {
            (list as? [[String: Any]] ?? []).prefix(30).map { f in
                let image = (f["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
                return "  \(image)  \(f["symbol"] as? String ?? "?")"
            }
        }
        let exception = body["exception"] as? [String: Any] ?? [:]
        let threads = body["threads"] as? [[String: Any]] ?? []
        let crashed = body["faultingThread"] as? Int ?? 0
        var lines = ["\(head["app_name"] ?? "?") \(head["app_version"] ?? "?") (\(head["build_version"] ?? "?")), \(head["os_version"] ?? "?")",
                     [exception["type"], exception["signal"], exception["subtype"]].compactMap { $0 as? String }.joined(separator: " ")]
        if let last = body["lastExceptionBacktrace"] { lines += ["exception thrown at:"] + frames(last) }
        lines += ["crashed:"] + frames(threads.indices.contains(crashed) ? threads[crashed]["frames"] : nil)
        return lines.joined(separator: "\n").replacingOccurrences(of: home, with: "~")
    }
}
