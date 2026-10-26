import AppKit
import FuseKit
import Combine
import LunteCore
import Sparkle
import SwiftUI

@main
struct LunteApp: App {
    @NSApplicationDelegateAdaptor private var menuBar: MenuBar

    var body: some Scene { Settings { EmptyView() } } // ponytail: a menu bar app; the menu bar item is all there is
}

/// The menu bar item: the fuse, drawn live over its button, and the popover under it. MenuBarExtra only takes a still
/// image, so the item is ours.
@MainActor
final class MenuBar: NSObject, NSApplicationDelegate {
    private lazy var model = GameModel() // lazy, so a preview run never starts the real game
    /// Sparkle stays off until a release sets SUPublicEDKey in Info.plist.
    private let updater: SPUStandardUpdaterController? =
        (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var item: NSStatusItem!
    private let fuse = FuseView()
    private var panel: MenuPanel!
    private var watching: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let dir = UserDefaults.standard.string(forKey: "PopoverShots") { return PopoverShots.render(to: dir) }
        #endif
        item = NSStatusBar.system.statusItem(withLength: FuseScene.fuseWidth + 2 * FuseView.margin)
        guard let button = item.button else { return }
        fuse.frame = button.bounds
        fuse.autoresizingMask = [.width, .height]
        fuse.resize = { [item] in item?.length = $0 }
        button.addSubview(fuse)
        Blast.icon = fuse
        button.target = self
        button.action = #selector(toggle)
        panel = MenuPanel(PopoverView(model: model, updater: updater))
        panel.closed = { [weak self] in
            self?.item.button?.highlight(false)
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "FuseDemo") { return demo() }
        if let clip = UserDefaults.standard.string(forKey: "HeroDemo") { return hero(clip) }
        #endif
        watching = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.render() }
        render()
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "PanelShot") { panelShot(path) }
        #endif
    }

    #if DEBUG
    /// `Lunte -PanelShot OUT.png`: opens the real panel under the real item, draws it to OUT.png, prints where it sits
    /// against the item, and quits.
    private func panelShot(_ path: String) {
        Task {
            try? await Task.sleep(for: .seconds(1)) // the menu bar places the item first
            toggle()
            try? await Task.sleep(for: .seconds(1.5))
            guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("panel", panel.frame, "item", item.button?.window?.frame ?? .zero, "highlighted", item.button?.isHighlighted ?? false)
            NSApp.terminate(nil)
        }
    }

    /// `open dist/Lunte.app --args -FuseDemo YES`: the menu bar fuse plays every state on a loop, instead of the game's.
    private func demo() {
        Task {
            while true {
                for (wait, look) in FusePreviews.demo {
                    if look.phase == .fusing { Blast.run(fuse: wait, sound: false) { _ in } } // the screen's show too, without the sound
                    fuse.show(look)
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
        }
    }

    private static var entrance: DispatchSourceSignal?

    /// The README's clips (scripts/hero.sh): where the fuse starts, then the look each prompt brings.
    static let clips: [String: [FuseLook]] = [
        "fuse": [FuseLook(), FuseLook(left: 0.6, prompt: 1, bite: 0.4), FuseLook(left: 0.15, prompt: 2, bite: 0.45),
                 FuseLook(left: 0.5, prompt: 3), FuseLook(left: 1, prompt: 4)], // back where it started, so it loops
        "heat": [FuseLook(), FuseLook(left: 0.6, prompt: 1, bite: 0.4)],
        "cool": [FuseLook(left: 0.4), FuseLook(left: 0.8, prompt: 1)],
        "close": [FuseLook(left: 0.55), FuseLook(left: 0.12, prompt: 1, bite: 0.43), FuseLook(left: 0.5, prompt: 2)],
        "boom": [FuseLook(), FuseLook(left: 0.6, prompt: 1, bite: 0.4), FuseLook(left: 0.2, prompt: 2, bite: 0.4),
                 FuseLook(phase: .fusing, left: 0)],
        "chain": [FuseLook(phase: .blown), FuseLook(phase: .blown, heat: 0.6), FuseLook(phase: .blown, name: "Chain reaction", tier: 2),
                  FuseLook(phase: .blown, name: "Meltdown", tier: 3)],
    ]

    /// `LUNTE_LOG=<spare dir>/events.jsonl Lunte -HeroDemo boom` (scripts/hero.sh): prompts from the hook play one of
    /// `clips` instead of the game, and a Boom blows after a second of silence. The prompt after the last starts it over.
    /// Nothing is rated, logged or sent. The item keeps one width, so nothing beside it moves, and it prints where it
    /// sits, for the recording: `at minX maxX barHeight screenWidth`.
    private func hero(_ clip: String) {
        guard let script = Self.clips[clip] else { return print("HeroDemo: no clip \(clip); try \(Self.clips.keys.sorted())") }
        let fd = ScorerSocket.listen()
        guard fd >= 0 else { print("HeroDemo: can't listen at \(ScorerSocket.url.path)"); return NSApp.terminate(nil) }
        let prompts = AsyncStream<Void> { prompt in
            DispatchQueue.global().async {
                while true {
                    let conn = accept(fd, nil, nil)
                    guard conn >= 0 else { continue }
                    var wait = timeval(tv_sec: 1, tv_usec: 0)
                    setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
                    _ = FileHandle(fileDescriptor: conn, closeOnDealloc: true).readDataToEndOfFile() // what it says doesn't matter
                    prompt.yield()
                }
            }
        }
        // `-HeroItem` wide, 180 by default: enough for "Chain reaction", with an empty left end for macOS's recording badge,
        // which it draws over the item, so the recording can start past it with the fuse in view. Too wide for the menu
        // bar, and macOS hides the fuse to make room for the badge.
        fuse.resize = { _ in }
        item.length = UserDefaults.standard.object(forKey: "HeroItem") as? Double ?? 180
        if script[0].phase == .lit {
            // It opens as a new session does, laying out a fresh fuse, once the recording has started (SIGUSR1). Till
            // then it's out of sight, and a quiet Boom, which a fresh fuse comes after.
            fuse.alphaValue = 0
            fuse.show(FuseLook(phase: .blown, quiet: true))
            signal(SIGUSR1, SIG_IGN)
            let start = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            start.setEventHandler { [fuse] in
                fuse.show(script[0])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fuse.alphaValue = 1 } // once the Boom's word is gone
            }
            start.resume()
            Self.entrance = start
        } else {
            fuse.show(script[0])
        }
        Task {
            try? await Task.sleep(for: .seconds(1)) // the menu bar places the item first
            let frame = item.button?.window?.frame ?? .zero
            print("at", Int(frame.minX), Int(frame.maxX), Int(frame.height), Int(NSScreen.main?.frame.width ?? 0))
            fflush(stdout)
            var at = 0
            for await _ in prompts {
                at += 1
                guard at < script.count else { at = 0; fuse.show(script[0]); continue }
                if script[at - 1].phase == .lit { // the breeze while it's "rated"
                    fuse.show(FuseLook(left: script[at - 1].left, prompt: Double(at), rating: true))
                }
                try? await Task.sleep(for: .seconds(0.8))
                fuse.show(script[at])
                if script[at].phase == .fusing {
                    Blast.run(fuse: FuseScene.raceFor + 1, sound: false) { [fuse] _ in fuse.show(FuseLook(phase: .blown)) }
                }
            }
        }
    }
    #endif

    private func render() {
        fuse.show(model.fuseLook)
        let label = model.connected ? model.sentence : "Lunte, not connected yet"
        item.button?.setAccessibilityLabel(label)
        item.button?.toolTip = label
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if panel.isVisible || panel.justClosed { return panel.dismiss() }
        NSApp.activate() // so the Boom's line takes typing
        panel.show(under: button)
        DispatchQueue.main.async { button.highlight(true) } // after the click's own highlight lets go
    }
}

/// The popover's sheet, opened the way the system's own menu bar items open theirs (Battery, Wi-Fi): no arrow, a
/// material as bright as theirs, the top pinned just under the item, and closed by a click anywhere else, or Escape.
/// While it's open, it grows and shrinks with its content over `resize`, as the content expands or collapses.
final class MenuPanel: NSPanel {
    static let resize = 0.25
    static let expand = Animation.easeInOut(duration: resize) // what the content uses, so the two move together
    var closed: () -> Void = {}
    private var closedAt = Date.distantPast

    init(_ content: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 308, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        let material = NSVisualEffectView()
        material.material = .sheet // near white like Battery's (≈247); .menu draws a darker grey (≈221)
        material.state = .active
        material.maskImage = Self.rounded(13)
        let host = NSHostingView(rootView: content.fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] in self?.fit($0) }
            // Never taller than the panel, even while the content has grown and the panel is catching up: a frame
            // without the 0 takes the content's height, and the host centres it, which nudges everything down.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top))
        host.autoresizingMask = [.width, .height]
        material.addSubview(host)
        contentView = material
    }

    override var canBecomeKey: Bool { true }

    /// The click that closed it by landing on the item shouldn't open it again.
    var justClosed: Bool { Date().timeIntervalSince(closedAt) < 0.3 }

    func show(under button: NSStatusBarButton) {
        // By where the item is: its own window has no screen, and with the menu bar hidden it sits above the screen.
        guard let item = button.window?.frame,
              let screen = NSScreen.screens.first(where: { $0.frame.minX <= item.midX && item.midX < $0.frame.maxX })?.frame else { return }
        setFrameTopLeftPoint(NSPoint(x: min(item.minX, screen.maxX - frame.width - 8), y: min(item.minY, screen.maxY) - 4))
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        closedAt = Date()
        closed()
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    /// As tall as the content, the top where it was: at once while it's closed, else in step with the content.
    private func fit(_ size: CGSize) {
        guard size.height > 0, size != frame.size else { return }
        let to = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        guard isVisible else { return setFrame(to, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resize
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(to, display: true)
        } completionHandler: { [weak self] in
            self?.invalidateShadow()
        }
    }

    /// A rounded rectangle that stretches, as the material's mask.
    private static func rounded(_ radius: CGFloat) -> NSImage {
        let side = 2 * radius + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
