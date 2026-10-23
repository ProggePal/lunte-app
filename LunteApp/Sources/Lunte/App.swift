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
            PopoverView(model: model, updater: updater)
        } label: {
            Image(nsImage: menuBarImage(model.state, connected: model.connected, fusing: model.fusing, blown: model.testBlown))
                .accessibilityLabel(model.connected ? model.sentence : "Lunte, not connected yet")
        }
        .menuBarExtraStyle(.window)
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

/// Opened straight from Downloads, macOS runs a temporary copy that vanishes on reboot. Ask to be moved instead.
@MainActor
func translocated() -> Bool {
    guard Bundle.main.bundlePath.contains("/AppTranslocation/") else { return false }
    Alerts.tell("Move Lunte to Applications", "macOS is running a temporary copy of Lunte, so Claude Code can't reach it. Drag Lunte into Applications and open it from there.")
    return true
}

/// Adds the bundled plugin's marketplace and installs the plugin, finding `claude` through a login shell.
func installPlugin() async -> (ok: Bool, output: String) {
    let plugin = Bundle.main.resourceURL?.appending(path: "plugin").path ?? ""
    let script = """
    export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
    ok() { out=$("$@" 2>&1) || [[ $out == *[Aa]lready* ]] || { print -r -- "$out"; exit 1 } }
    ok claude plugin marketplace add "$1"
    ok claude plugin install lunte@lunte
    """
    return await Task.detached { () -> (ok: Bool, output: String) in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script, "zsh", plugin]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (false, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }.value
}

@MainActor
enum Alerts {
    /// "Submit a prompt…": your name and your idea, written as the prompt an agent would build it from.
    /// Returns them trimmed, or nil on Cancel. An empty prompt says so instead of sending nothing.
    static func submitPrompt() -> (name: String, prompt: String)? {
        let alert = NSAlert()
        alert.messageText = "Something you want to see in Lunte?"
        alert.informativeText = "Write your prompt and your name. Agents will build it, and if it's good, we keep it. Credits in the changelog."
        alert.addButton(withTitle: "Submit")
        alert.addButton(withTitle: "Cancel")
        let width: CGFloat = 320
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 160))
        let name = NSTextField(frame: NSRect(x: 0, y: 136, width: width, height: 24))
        name.placeholderString = "Your name"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 128))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isRichText = false
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.autoresizingMask = [.width]
        text.isAutomaticQuoteSubstitutionEnabled = false
        scroll.documentView = text
        box.addSubview(name)
        box.addSubview(scroll)
        name.nextKeyView = text
        alert.accessoryView = box
        alert.window.initialFirstResponder = name
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let prompt = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { tell("Write a prompt first", "Describe what you'd like Lunte to do, the way you'd ask an agent to build it."); return nil }
        return (name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), prompt)
    }

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
