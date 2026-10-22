// lunte-hook: Claude Code's UserPromptSubmit hook (contract §2).
// stdin JSON -> one Event in the log. Prints nothing and exits 0 on every path: stdout would land in the chat.
import Foundation
import LunteCore

let input = FileHandle.standardInput.readDataToEndOfFile()
// ponytail: stdin that isn't a JSON object isn't a prompt, so nothing is logged
if let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] {
    let burn = Classifier.classify(json["prompt"] as? String ?? "")
    try? EventLog.append(Event(ts: Date().timeIntervalSince1970, burn: burn, sid: json["session_id"] as? String ?? ""))
}
exit(0)
