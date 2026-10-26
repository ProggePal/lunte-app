// lunte-hook: Claude Code's UserPromptSubmit hook (contract §2), and three commands for fuse setup (§8).
// As the hook (no arguments): stdin JSON -> one Event in the log. Prints nothing and exits 0 on every path: stdout
// would land in the chat. The commands are only ever run by hand or by your AI, so they may print.
import Foundation
import LunteCore

switch CommandLine.arguments.dropFirst().first {
case "setup": // the steps for your AI; the setup prompt only points here
    print(Fuse.setupText)
case "messages": // the messages your AI rates: one JSON line each, text cut short
    let all = Transcript.all(since: Date().timeIntervalSince1970 - 60 * 86400)
    for m in Fuse.candidates(all) {
        let row: [String: Any] = ["sid": m.sid, "ts": (m.ts * 1000).rounded() / 1000, "text": String(m.text.prefix(300))]
        if let d = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes]) {
            print(String(decoding: d, as: UTF8.self))
        }
    }
    FileHandle.standardError.write(Data("\(min(all.count, 300)) of your \(all.count) messages from the last 60 days\n".utf8))
case "check-fuse": // are labels.json (heat and cool) and vibes.json right, and can Lunte find the rated messages?
    guard let data = try? Data(contentsOf: Fuse.labelsURL) else { print("No file at \(Fuse.labelsURL.path)"); exit(1) }
    do {
        let labels = try JSONDecoder().decode(FuseLabels.self, from: data)
        let known = Transcript.all(since: (labels.labels.map(\.ts).min() ?? 0) - 60)
        let found = labels.labels.filter { l in known.contains { $0.sid == l.sid && abs($0.ts - l.ts) < 1 } }.count
        var problems = labels.problems + (found < labels.labels.count ? ["\(labels.labels.count - found) ratings point at messages Lunte can't find; copy sid and ts exactly"] : [])
        if labels.missingCool > 0 { problems.append("\(labels.missingCool) messages have no \"cool\" rating; rate cool 0–3 for every message") }
        var vibes = 0
        if let v = try? Data(contentsOf: Fuse.vibesURL) {
            do {
                let file = try JSONDecoder().decode(FuseVibes.self, from: v)
                problems += file.problems.map { "vibes.json: " + $0 }
                vibes = file.vibes.count
            } catch { problems.append("vibes.json isn't in the expected shape: \(error)") }
        } else {
            problems.append("No vibes.json yet")
        }
        print(problems.isEmpty ? "OK: \(labels.labels.count) messages rated for heat and cool, all found, and \(vibes) session names. Lunte will tune the fuse now." : problems.joined(separator: "\n"))
        exit(problems.isEmpty ? 0 : 1)
    } catch {
        print("labels.json isn't in the expected shape: \(error)")
        exit(1)
    }
default: // the hook
    let input = FileHandle.standardInput.readDataToEndOfFile()
    // ponytail: stdin that isn't a JSON object isn't a prompt, so nothing is logged
    if let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
       case let text = Classifier.human(json["prompt"] as? String ?? ""), !text.isEmpty { // agent and system messages aren't you
        let ts = Date().timeIntervalSince1970
        let rated = ScorerSocket.send(ts: ts, text: text) // the app's model rates it and logs the heat
        try? EventLog.append(Event(ts: ts, burn: Classifier.classify(text), sid: json["session_id"] as? String ?? "",
                                   rated: rated ? true : nil))
    }
    exit(0)
}
