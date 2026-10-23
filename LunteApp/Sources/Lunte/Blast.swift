import AppKit
import QuartzCore

/// The Boom on screen, from the menu bar icon, in native Core Animation particles. While the fuse burns, sparks drip
/// from the icon. In the last second the screen dims and the fuse spits harder. Then it blows from the icon: a burst
/// of sparks falling down the screen and a shockwave. Clicks pass through. With Reduce Motion it's just the wait.
@MainActor
enum Blast {
    private static var panel: NSPanel?
    private static var job: Task<Void, Never>?

    /// Burns for `fuse` seconds, then blows and calls `boom` (the sound, the Club). A new Blast replaces a running one.
    static func run(fuse: Double, boom: @escaping @MainActor () -> Void) {
        job?.cancel()
        panel?.close()
        panel = nil
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let (screen, icon) = iconOnScreen() else {
            job = Task { try? await Task.sleep(for: .seconds(fuse)); if !Task.isCancelled { boom() } }
            return
        }
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver // above the menu bar, so the sparks start at the icon
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        p.contentView = view
        p.setFrame(screen.frame, display: false)
        p.orderFrontRegardless()
        panel = p

        let root = view.layer!
        let at = CGPoint(x: icon.midX - screen.frame.minX, y: icon.minY - screen.frame.minY) // the icon's bottom edge; y points up
        let dim = CALayer()
        dim.frame = root.bounds
        dim.backgroundColor = NSColor.black.cgColor
        dim.opacity = 0
        root.addSublayer(dim)
        let drip = emitter(at: at, cells: sparks(birthRate: 14, velocity: 50, range: .pi / 4, down: true, lifetime: 1.6))
        root.addSublayer(drip)

        job = Task {
            try? await Task.sleep(for: .seconds(max(0, fuse - 1)))
            guard !Task.isCancelled else { return }
            fade(dim, to: 0.35, over: 0.9) // the last second
            drip.birthRate = 4
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            drip.birthRate = 0
            fade(dim, to: 0, over: 0.5)
            let burst = emitter(at: at, cells: sparks(birthRate: 500, velocity: 420, range: .pi * 2, down: false, lifetime: 2.6))
            root.addSublayer(burst)
            root.addSublayer(shockwave(at: at))
            boom()
            try? await Task.sleep(for: .milliseconds(120))
            burst.birthRate = 0 // one burst, then gravity does the rest
            try? await Task.sleep(for: .seconds(3))
            p.close()
            if panel === p { panel = nil }
        }
    }

    /// The menu bar icon's frame and its screen. MenuBarExtra hides its NSStatusItem, so this finds the status bar
    /// window that holds it. ponytail: falls back to the top right of the main screen if macOS ever renames that class.
    private static func iconOnScreen() -> (NSScreen, NSRect)? {
        if let w = NSApp.windows.first(where: { $0.className.contains("NSStatusBarWindow") && $0.isVisible }),
           let screen = w.screen ?? NSScreen.main {
            return (screen, w.frame)
        }
        guard let screen = NSScreen.main else { return nil }
        return (screen, NSRect(x: screen.frame.maxX - 140, y: screen.frame.maxY - 24, width: 40, height: 24))
    }

    private static func emitter(at point: CGPoint, cells: [CAEmitterCell]) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.emitterPosition = point
        e.emitterShape = .point
        e.renderMode = .additive // sparks brighten where they overlap
        e.emitterCells = cells
        e.beginTime = CACurrentMediaTime()
        return e
    }

    /// Yellow, orange and red sparks. `down` aims them at the floor (a drip); otherwise they fly every way (a burst).
    private static func sparks(birthRate: Float, velocity: CGFloat, range: CGFloat, down: Bool, lifetime: Float) -> [CAEmitterCell] {
        [NSColor.systemYellow, .systemOrange, .systemRed].map { color in
            let c = CAEmitterCell()
            c.contents = dot
            c.color = color.cgColor
            c.birthRate = birthRate / 3
            c.lifetime = lifetime
            c.lifetimeRange = lifetime / 3
            c.velocity = velocity
            c.velocityRange = velocity / 2
            c.emissionLongitude = down ? -.pi / 2 : 0
            c.emissionRange = range
            c.yAcceleration = down ? -260 : -520 // gravity
            c.scale = down ? 0.12 : 0.2
            c.scaleRange = 0.08
            c.scaleSpeed = -0.06
            c.alphaSpeed = -1 / lifetime
            return c
        }
    }

    private static func shockwave(at point: CGPoint) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = NSColor.systemOrange.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        let circle = { (r: CGFloat) in CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2), transform: nil) }
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = circle(6)
        grow.toValue = circle(260)
        let width = CABasicAnimation(keyPath: "lineWidth")
        width.fromValue = 10
        width.toValue = 1
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.9
        fadeOut.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, width, fadeOut]
        group.duration = 0.7
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "shockwave")
        return ring
    }

    private static func fade(_ layer: CALayer, to opacity: Float, over seconds: Double) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = layer.presentation()?.opacity ?? layer.opacity
        a.toValue = opacity
        a.duration = seconds
        layer.opacity = opacity
        layer.add(a, forKey: "fade")
    }

    /// A soft white disc; each spark tints it.
    private static let dot: CGImage = {
        let size = 32
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: size - 8, height: size - 8))
        return ctx.makeImage()!
    }()
}
