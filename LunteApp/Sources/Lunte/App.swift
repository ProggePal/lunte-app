import AppKit
import LunteCore
import Sparkle
import SwiftUI

@main
struct LunteApp: App {
    @StateObject private var model = GameModel()
    /// Sparkle stays off until a release sets SUPublicEDKey in Info.plist.
    private let updater: SPUStandardUpdaterController? =
        (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        MenuBarExtra {
            LunteMenu(model: model, updater: updater)
        } label: {
            Text(Game.stickText(model.state))
        }
    }
}

struct LunteMenu: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?

    var body: some View {
        Text(model.statusLine)
        if model.whyBoom != nil {
            Button("Say why…", action: model.sayWhy)
        }
        Divider()
        if let club = model.club {
            Button("Club \(club) · copy code") { copyToClipboard(club) }
            ForEach(model.recent.reversed(), id: \.seq) { Text(model.describe($0)) }
            Button("Leave Club", action: model.leaveClub)
        } else {
            Button("Create a Club…", action: model.createClub)
            Button("Join a Club…", action: model.joinClub)
        }
        Divider()
        Button("Test your Boom", action: model.playBoom)
        Toggle("Sound", isOn: $model.soundOn)
        Button("Connect to Claude Code", action: connectToClaude)
        Button("Feedback & ideas…") { NSWorkspace.shared.open(URL(string: "https://github.com/ProggePal/lunte-app/issues/new")!) }
        Button("Check for Updates…") { updater?.checkForUpdates(nil) }
            .disabled(updater == nil)
        Divider()
        Button("Quit Lunte") { NSApp.terminate(nil) }
    }
}

/// Claude Code runs a cached copy of the plugin, so the hook can't find the app by a relative path.
/// The plugin calls this fixed link instead, and every launch points it at this copy of the app.
@MainActor
func linkHook() {
    guard !translocated() else { return }
    let fm = FileManager.default
    let link = fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Lunte/lunte-hook")
    guard let hook = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "lunte-hook"),
          fm.fileExists(atPath: hook.path),
          (try? fm.destinationOfSymbolicLink(atPath: link.path)) != hook.path else { return }
    try? fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fm.removeItem(at: link)
    try? fm.createSymbolicLink(at: link, withDestinationURL: hook)
}

/// Adds the bundled plugin's marketplace and installs the plugin, finding `claude` through a login shell.
/// Opened straight from Downloads, macOS runs a temporary copy that vanishes on reboot. Ask to be moved instead.
@MainActor
func translocated() -> Bool {
    guard Bundle.main.bundlePath.contains("/AppTranslocation/") else { return false }
    Alerts.tell("Move Lunte to Applications", "macOS is running a temporary copy of Lunte, so Claude Code can't reach it. Drag Lunte into Applications and open it from there.")
    return true
}

@MainActor
func connectToClaude() {
    guard !translocated() else { return }
    let plugin = Bundle.main.resourceURL?.appending(path: "plugin").path ?? ""
    let script = """
    export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
    ok() { out=$("$@" 2>&1) || [[ $out == *[Aa]lready* ]] || { print -r -- "$out"; exit 1 } }
    ok claude plugin marketplace add "$1"
    ok claude plugin install lunte@lunte
    """
    Task {
        let (status, output) = await Task.detached { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script, "zsh", plugin]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
        if status == 0 {
            Alerts.tell("Almost there", "Open a new Claude Code chat and type:\n\nthis is a test 3 2 1 pow\n\nThat's your first Boom.")
        } else {
            Alerts.tell("Couldn't connect to Claude Code", String(output.suffix(800)))
        }
    }
}

@MainActor
enum Alerts {
    /// An alert with one text field per placeholder. Returns the trimmed values, or nil on Cancel.
    static func ask(_ title: String, _ info: String, fields: [String]) -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let width: CGFloat = 260, height: CGFloat = 24, gap: CGFloat = 8
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: CGFloat(fields.count) * (height + gap) - gap))
        let inputs = fields.enumerated().map { i, placeholder in
            let field = NSTextField(frame: NSRect(x: 0, y: box.frame.height - CGFloat(i + 1) * height - CGFloat(i) * gap, width: width, height: height))
            field.placeholderString = placeholder
            box.addSubview(field)
            return field
        }
        zip(inputs, inputs.dropFirst()).forEach { $0.nextKeyView = $1 }
        alert.accessoryView = box
        alert.window.initialFirstResponder = inputs.first
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return inputs.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Started from the run loop, not from inside a main-actor job: a modal opened inside a job blocks every
    /// other main-actor job (the log watcher, polling) until it's dismissed.
    nonisolated static func tell(_ title: String, _ info: String = "") {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = info
                NSApp.activate()
                alert.runModal()
            }
        }
    }
}
