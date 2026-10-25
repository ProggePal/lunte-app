import AppKit
import FuseKit
import QuartzCore

/// The Boom on screen, from the fuse in the menu bar, in native Core Animation: the one show. The moment the fuse has
/// burnt through, the whole screen goes dark, and stays dark through the silence. Then the fizz, and it blows in the
/// stillness: a flash and the sound, then time eases back up as the blast opens out, a bloom of light, two shockwaves,
/// sparks, embers and smoke, while the dark drains away. Clicks pass through. With Reduce Motion it's just the wait.
// Why: a beat of stillness on impact (hq: docs/research/game-feel-and-motivation.md, hitstop)
@MainActor
enum Blast {
    private static var panel: NSPanel?
    private static var job: Task<Void, Never>?

    /// How late a fuse can run by the wall clock and still blow. Any later, the Mac slept through the wait.
    static let lateBy = 2.0
    /// How long the screen takes to go dark, once the fuse has burnt through.
    static let dimFor = 0.5

    /// The menu bar fuse, set by `MenuBar`: where the show comes from.
    static weak var icon: FuseView?

    /// Burns for `fuse` seconds, then blows and calls `boom(true)` (the Club). With `sound`, the fizz starts `Bang.fizz`
    /// seconds early, so the bang lands with the flash. If the Mac slept through the wait, it skips the sound and the
    /// show and calls `boom(false)`. A new Blast replaces a running one.
    static func run(fuse: Double, sound: Bool, boom: @escaping @MainActor (_ blew: Bool) -> Void) {
        job?.cancel()
        panel?.close()
        panel = nil
        // Why: Task.sleep keeps counting while the Mac sleeps, and a bang the moment the lid opens points straight at
        // you (docs/why.md#two-clocks)
        let deadline = Date().addingTimeInterval(fuse)
        let late = { Date().timeIntervalSince(deadline) > lateBy }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let (screen, fuseAt) = icon?.startOnScreen() else {
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
        p.level = .screenSaver // above the menu bar, so the show starts at the fuse
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        p.contentView = view
        p.setFrame(screen.frame, display: false)
        p.orderFrontRegardless()
        panel = p

        let root = view.layer!
        let at = CGPoint(x: fuseAt.x - screen.frame.minX, y: fuseAt.y - screen.frame.minY) // y points up
        // The dark and the flash keep real time; the blast lives in `world`, whose time is eased.
        let tint = CAGradientLayer()
        tint.type = .radial
        tint.frame = root.bounds
        let centre = CGPoint(x: at.x / root.bounds.width, y: at.y / root.bounds.height), reach = 0.9
        tint.startPoint = centre
        tint.endPoint = CGPoint(x: centre.x + reach, y: centre.y + reach * root.bounds.width / root.bounds.height)
        tint.colors = [NSColor(srgbRed: 1, green: 0.45, blue: 0.12, alpha: 0.18).cgColor,
                       NSColor(srgbRed: 0.04, green: 0.01, blue: 0, alpha: 0.72).cgColor]
        tint.opacity = 0
        let world = CALayer()
        world.frame = root.bounds
        let flash = CALayer()
        flash.frame = root.bounds
        flash.backgroundColor = NSColor(srgbRed: 1, green: 0.9, blue: 0.75, alpha: 1).cgColor
        flash.opacity = 0
        root.addSublayer(tint)
        root.addSublayer(world)
        root.addSublayer(flash)

        let fizzle = { p.close(); if panel === p { panel = nil }; boom(false) } // slept through: no show, no sound, no blast
        job = Task {
            // The fuse burns through, the lights go down, and it's silent in the dark. Then the fizz, and it blows.
            try? await Task.sleep(for: .seconds(min(FuseScene.raceFor, max(0, fuse - dimFor))))
            guard !Task.isCancelled else { return }
            if late() { return fizzle() }
            fade(tint, to: 1, over: dimFor, .easeOut)
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow - Bang.fizz)))
            guard !Task.isCancelled else { return }
            if late() { return fizzle() }
            if sound { Bang.play() }
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            if late() { return fizzle() }
            pace(world, speed(0))
            pulse(flash, to: 0.5, over: 0.45)
            fade(tint, to: 0, over: 2.4)
            let blast = bang(at: at, in: world)
            let stopAt = world.convertTime(CACurrentMediaTime(), from: nil) + 0.15 // one burst, in the world's own time
            boom(true)
            // Time eases back up to speed as the blast opens out.
            while !Task.isCancelled {
                let since = -deadline.timeIntervalSinceNow
                if world.convertTime(CACurrentMediaTime(), from: nil) >= stopAt { blast.forEach { $0.birthRate = 0 } }
                pace(world, speed(since))
                if since > FuseScene.speedUp { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            blast.forEach { $0.birthRate = 0 }
            try? await Task.sleep(for: .seconds(5))
            p.close()
            if panel === p { panel = nil }
        }
    }

    /// How fast the blast runs, by seconds since the bang: from a near stop, easing back up to speed.
    static func speed(_ since: Double) -> Float {
        let u = min(1, max(0, since / FuseScene.speedUp))
        return Float(0.05 + 0.95 * u * u)
    }

    /// The blast, starting in the stillness: a bloom of light, two shockwaves, a cloud of smoke, sparks and embers.
    /// Returns the emitters, to stop their births after one burst.
    private static func bang(at: CGPoint, in world: CALayer) -> [CAEmitterLayer] {
        let smoke = emitter(at: at, in: world, cells: smokeCells())
        smoke.renderMode = .unordered
        let bloom = CAGradientLayer()
        bloom.type = .radial
        bloom.bounds = CGRect(x: 0, y: 0, width: 520, height: 520)
        bloom.position = at
        bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloom.endPoint = CGPoint(x: 1, y: 1)
        bloom.colors = [NSColor(srgbRed: 1, green: 0.97, blue: 0.85, alpha: 1).cgColor,
                        NSColor(srgbRed: 1, green: 0.55, blue: 0.15, alpha: 0.55).cgColor,
                        NSColor(srgbRed: 1, green: 0.3, blue: 0.05, alpha: 0).cgColor]
        bloom.locations = [0, 0.35, 1]
        bloom.opacity = 0
        world.addSublayer(bloom)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.05
        grow.toValue = 1
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fadeOut = CAKeyframeAnimation(keyPath: "opacity")
        fadeOut.values = [1, 0.9, 0]
        fadeOut.keyTimes = [0, 0.3, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fadeOut]
        group.duration = 1.1
        bloom.add(group, forKey: "bloom")
        world.addSublayer(shockwave(at: at, colour: .systemOrange, to: 300, width: 12, over: 0.8))
        world.addSublayer(shockwave(at: at, colour: .white, to: 200, width: 3, over: 0.6))
        let embers = emitter(at: at, in: world, cells: sparks(birthRate: 220, velocity: 160, range: .pi * 2, down: false, lifetime: 4.5))
        let burst = emitter(at: at, in: world, cells: sparks(birthRate: 600, velocity: 430, range: .pi * 2, down: false, lifetime: 2.6))
        return [smoke, embers, burst]
    }

    private static func emitter(at point: CGPoint, in world: CALayer, cells: [CAEmitterCell]) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.emitterPosition = point
        e.emitterShape = .point
        e.renderMode = .additive // sparks brighten where they overlap
        e.emitterCells = cells
        e.beginTime = world.convertTime(CACurrentMediaTime(), from: nil) // starts now, in the world's own time
        world.addSublayer(e)
        return e
    }

    /// Yellow, orange and red sparks. `down` aims them at the floor; otherwise they fly every way (a burst).
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

    /// Wisps of smoke, dark and light, rolling out and down from the fuse, swelling, drifting up a little, fading.
    private static func smokeCells() -> [CAEmitterCell] {
        [(0.2, 0.4), (0.45, 0.28)].map { grey, alpha in
            let c = CAEmitterCell()
            c.contents = puff
            c.color = NSColor(srgbRed: grey + 0.03, green: grey, blue: grey - 0.02, alpha: alpha).cgColor
            c.birthRate = 90
            c.lifetime = 3
            c.lifetimeRange = 1
            c.velocity = 150
            c.velocityRange = 90
            c.emissionLongitude = -.pi / 2
            c.emissionRange = .pi * 1.3
            c.yAcceleration = 18 // smoke rises
            c.scale = 0.7
            c.scaleRange = 0.35
            c.scaleSpeed = 0.45
            c.spin = 0.3
            c.spinRange = 0.8
            c.alphaSpeed = -0.3
            return c
        }
    }

    private static func shockwave(at point: CGPoint, colour: NSColor, to radius: CGFloat, width: CGFloat, over: Double) -> CAShapeLayer {
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
        group.duration = over
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "shockwave")
        return ring
    }

    /// Plays `layer` at `speed` from where it is now, so what's in it slows down or speeds up without a jump.
    private static func pace(_ layer: CALayer, _ speed: Float) {
        guard layer.speed != speed else { return }
        let now = CACurrentMediaTime()
        layer.timeOffset = layer.convertTime(now, from: nil)
        layer.beginTime = now
        layer.speed = speed
    }

    /// Flashes `layer` up to `opacity` and back down to nothing.
    private static func pulse(_ layer: CALayer, to opacity: Float, over seconds: Double) {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, opacity, 0]
        a.keyTimes = [0, 0.12, 1]
        a.duration = seconds
        layer.add(a, forKey: "pulse")
    }

    private static func fade(_ layer: CALayer, to opacity: Float, over seconds: Double, _ timing: CAMediaTimingFunctionName = .default) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.timingFunction = CAMediaTimingFunction(name: timing)
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

    /// A soft white cloud, fading out to its edge; each puff of smoke tints it.
    private static let puff: CGImage = {
        let size = 96
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 0.55, 1])!
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()!
    }()
}
