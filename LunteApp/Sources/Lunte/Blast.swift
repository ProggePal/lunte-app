import AppKit
import FuseKit
import QuartzCore

/// The Boom on screen, from the menu bar icon, in native Core Animation particles: the one show. The wait is silent, as
/// if the fuse went out. In its last 3 seconds the room darkens around a warm glow at the fuse and sparks shoot out of
/// it; in the last 1.4 they slow down until they almost hang, as the menu bar does. Then it blows at full speed from the
/// icon: a flash, two shockwaves, and a burst of sparks and embers falling down the screen, as the dark drains away.
/// Clicks pass through. With Reduce Motion it's just the wait.
@MainActor
enum Blast {
    private static var panel: NSPanel?
    private static var job: Task<Void, Never>?

    /// How late a fuse can run by the wall clock and still blow. Any later, the Mac slept through the wait.
    static let lateBy = 2.0

    /// Burns for `fuse` seconds, then blows and calls `boom(true)` (the Club). With `sound`, the fizz starts `Bang.fizz`
    /// seconds early, so the bang lands with the burst. If the Mac slept through the wait, it skips the sound and the
    /// burst and calls `boom(false)`. A new Blast replaces a running one.
    static func run(fuse: Double, sound: Bool, boom: @escaping @MainActor (_ blew: Bool) -> Void) {
        job?.cancel()
        panel?.close()
        panel = nil
        // Why: Task.sleep keeps counting while the Mac sleeps, and a bang the moment the lid opens points straight at
        // you (docs/why.md#two-clocks)
        let deadline = Date().addingTimeInterval(fuse)
        let late = { Date().timeIntervalSince(deadline) > lateBy }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let (screen, icon) = iconOnScreen() else {
            job = Task {
                try? await Task.sleep(for: .seconds(max(0, fuse - Bang.fizz)))
                guard !Task.isCancelled else { return }
                if late() { return boom(false) }
                if sound { Bang.play() }
                try? await Task.sleep(for: .seconds(Bang.fizz))
                if !Task.isCancelled { boom(true) }
            }
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
        // Under where the fuse starts, which is where it fizzes and blows; y points up.
        let at = CGPoint(x: icon.maxX - FuseView.margin + FuseScene.start - screen.frame.minX, y: icon.minY - screen.frame.minY)
        // The room darkens toward the bang: a warm glow around the fuse, dark at the edges.
        let tint = CAGradientLayer()
        tint.type = .radial
        tint.frame = root.bounds
        let centre = CGPoint(x: at.x / root.bounds.width, y: at.y / root.bounds.height), reach = 1.1
        tint.startPoint = centre
        tint.endPoint = CGPoint(x: centre.x + reach, y: centre.y + reach * root.bounds.width / root.bounds.height)
        tint.colors = [NSColor(srgbRed: 1, green: 0.45, blue: 0.12, alpha: 0.25).cgColor,
                       NSColor(srgbRed: 0.14, green: 0.02, blue: 0, alpha: 0.62).cgColor]
        tint.opacity = 0
        root.addSublayer(tint)
        let flash = CALayer()
        flash.frame = root.bounds
        flash.backgroundColor = NSColor(srgbRed: 1, green: 0.88, blue: 0.68, alpha: 1).cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        // Sparks shooting out of where the fuse began, only once the show starts.
        let shoot = emitter(at: at, cells: sparks(birthRate: 40, velocity: 170, range: .pi * 0.7, down: true, lifetime: 1.6))
        shoot.birthRate = 0
        root.addSublayer(shoot)

        let fizzle = { p.close(); if panel === p { panel = nil }; boom(false) } // slept through: no show, no sound, no burst
        let slowMo = FuseScene.slowMo, show = min(FuseScene.takeover, fuse) // nothing, then the show, then its slow end
        job = Task {
            try? await Task.sleep(for: .seconds(max(0, fuse - show)))
            guard !Task.isCancelled else { return }
            if late() { return fizzle() }
            fade(tint, to: 0.6, over: max(0.1, show - slowMo))
            shoot.birthRate = 1
            try? await Task.sleep(for: .seconds(max(0, show - slowMo)))
            guard !Task.isCancelled else { return }
            if late() { return fizzle() }
            fade(tint, to: 1, over: slowMo)
            shoot.birthRate = 3 // harder, as it slows down
            pace(shoot, 0.3)
            try? await Task.sleep(for: .seconds(slowMo - Bang.fizz))
            guard !Task.isCancelled else { return }
            if late() { return fizzle() }
            if sound { Bang.play() } // the fizz, then the bang right on the burst
            pace(shoot, 0.08) // nearly still
            try? await Task.sleep(for: .seconds(Bang.fizz))
            guard !Task.isCancelled else { return }
            shoot.birthRate = 0
            pace(shoot, 1) // and time comes back with the bang
            pulse(flash, to: 0.45, over: 0.4)
            fade(tint, to: 0, over: 1.8)
            let burst = emitter(at: at, cells: sparks(birthRate: 500, velocity: 420, range: .pi * 2, down: false, lifetime: 2.6))
            let embers = emitter(at: at, cells: sparks(birthRate: 160, velocity: 150, range: .pi * 2, down: false, lifetime: 4.5))
            root.addSublayer(embers)
            root.addSublayer(burst)
            root.addSublayer(shockwave(at: at, colour: .systemOrange, to: 260, width: 10))
            boom(true)
            try? await Task.sleep(for: .milliseconds(90))
            root.addSublayer(shockwave(at: at, colour: .white, to: 180, width: 3))
            try? await Task.sleep(for: .milliseconds(30))
            burst.birthRate = 0 // one burst, then gravity does the rest
            embers.birthRate = 0
            try? await Task.sleep(for: .seconds(4.5))
            p.close()
            if panel === p { panel = nil }
        }
    }

    /// The menu bar item's button, set by `MenuBar`.
    static weak var icon: NSView?

    /// The menu bar item's frame and its screen, or nil when it isn't showing (hidden behind the notch, say).
    private static func iconOnScreen() -> (NSScreen, NSRect)? {
        guard let w = icon?.window, w.isVisible, let screen = w.screen else { return nil }
        return (screen, w.frame)
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

    private static func shockwave(at point: CGPoint, colour: NSColor, to radius: CGFloat, width: CGFloat) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = colour.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        let circle = { (r: CGFloat) in CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2), transform: nil) }
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = circle(6)
        grow.toValue = circle(radius)
        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = width
        thin.toValue = 1
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.9
        fadeOut.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, thin, fadeOut]
        group.duration = 0.7
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "shockwave")
        return ring
    }

    /// Plays `layer` at `speed` from where it is now, so its sparks slow down or speed up without a jump.
    private static func pace(_ layer: CALayer, _ speed: Float) {
        let now = CACurrentMediaTime()
        layer.timeOffset = layer.convertTime(now, from: nil)
        layer.beginTime = now
        layer.speed = speed
    }

    /// Flashes `layer` up to `opacity` and back down to nothing.
    private static func pulse(_ layer: CALayer, to opacity: Float, over seconds: Double) {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, opacity, 0]
        a.keyTimes = [0, 0.15, 1]
        a.duration = seconds
        layer.add(a, forKey: "pulse")
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
