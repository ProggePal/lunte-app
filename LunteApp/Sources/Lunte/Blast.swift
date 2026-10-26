import AppKit
import FuseKit

/// The Boom on screen, from the fuse in the menu bar: the one show. The menu bar fuse has already taken the screen dark
/// (`FuseView`), and it's silent. Then it blows in the stillness: the flash and the bang at once, then the
/// blast (`BlastScene`: a fireball, its light, a shockwave, sparks and faint smoke) opens out as time eases back up,
/// while the light comes back. Each Boom blows its own way. Clicks pass through. With Reduce Motion it's just the wait.
// Why: hitstop, a beat of stillness on impact (docs/why.md#boom-in-the-stillness)
@MainActor
enum Blast {
    private static var panel: NSPanel?
    private static var job: Task<Void, Never>?
    private static var renderer: BlastRenderer?
    private static var preparing = false

    /// How late a fuse can run by the wall clock and still blow. Any later, the Mac slept through the wait.
    static let lateBy = 2.0

    /// The menu bar fuse, set by `MenuBar`: where the show comes from.
    static weak var icon: FuseView?

    /// Burns for `fuse` seconds, then blows as `scene` and calls `boom(true)` (the Club). At a `volume` over 0, the bang is
    /// readied as the fuse lights, so it lands with the flash. If the Mac slept through the wait, it skips the sound
    /// and the show and calls `boom(false)`. A new Blast replaces a running one.
    static func run(fuse: Double, volume: Double, scene: BlastScene, boom: @escaping @MainActor (_ blew: Bool) -> Void) {
        job?.cancel()
        panel?.close()
        panel = nil
        prepare()
        // Why: Task.sleep keeps counting while the Mac sleeps, and a bang the moment the lid opens points straight at
        // you (docs/why.md#two-clocks)
        let deadline = Date().addingTimeInterval(fuse)
        let late = { Date().timeIntervalSince(deadline) > lateBy }
        Bang.prepare(pitch: scene.pitch, volume: volume)
        job = Task {
            // The fuse crawls and races out, then silence, then it blows: the flash and the bang together.
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            if late() { Bang.cancel(); return boom(false) } // slept through: no show, no sound
            Bang.fire()
            show(scene)
            boom(true)
        }
    }

    /// Compiles the blast's shaders off the main thread, well ahead of the bang: the fuse burns for seconds first.
    static func prepare() {
        guard renderer == nil, !preparing else { return }
        preparing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let made = BlastRenderer()
            Task { @MainActor in renderer = made; preparing = false }
        }
    }

    /// The blast over the fuse's screen, in a click-through panel above the menu bar, gone once it's over.
    private static func show(_ scene: BlastScene) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let renderer,
              let (screen, fuseAt) = icon?.startOnScreen() else { return }
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver // above the menu bar, so the show starts at the fuse
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let at = CGPoint(x: fuseAt.x - screen.frame.minX, y: fuseAt.y - screen.frame.minY) // y points up
        let view = BlastView(frame: NSRect(origin: .zero, size: screen.frame.size), renderer: renderer, scene: scene, at: at)
        view.done = { p.close(); if panel === p { panel = nil } }
        p.contentView = view
        p.setFrame(screen.frame, display: false)
        p.orderFrontRegardless()
        panel = p
        view.bang()
    }
}
