// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
//   moves OUT NAME…  the named moves from FusePreviews.moves: OUT.png magnified, twelve moments each, then at actual
//                    size; OUT.gif magnified at real speed, 50 fps, one after the other
//   plain FRAMES OUT WIDTH   a README clip's frames as they are, for scripts/hero.sh
//   bar FRAMES OUT light|dark   the README's menu bar frames, rounded, on a backdrop, for scripts/hero.sh
//   social FRAMES OUT.png   the repo's social preview, for scripts/hero.sh
//   icon OUT.iconset   the app's icon at every size, for iconutil
//   tour OUT [synth]   every move and every sound in one session (with `synth`, the flame is the synth instead of
//                    Resources/fuse.wav, to OUT-synth), on the stand-in screen with the fuse magnified and a
//                    caption for each move: the sounds mixed from the scene's own cues to OUT.wav, and OUT.mp4
//   fuses OUT FILE…  fuse loops side by side, each the flame in the same short session, to OUT.wav and OUT.mp4
//   blast OUT [KIND [SIZE]|close]…   the Boom on screen, from the race and the drops to the blast, for each kind (all
//                    of them and a close call by default): twelve moments to OUT-KIND.png, and every frame at 50 fps
//                    to OUT-KIND/, for ffmpeg
import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderFuse {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 5, args[1] == "plain" { return plain(args[2], args[3], Double(args[4])!) }
        if args.count == 5, args[1] == "bar" { return bar(args[2], args[3], dark: args[4] == "dark") }
        if args.count == 4, args[1] == "social" { return social(args[2], args[3]) }
        if args.count == 3, args[1] == "icon" { return icon(args[2]) }
        if args.count >= 3, args[1] == "blast" { return blast(args[2], Array(args[3...])) }
        if args.count >= 3, args[1] == "tour" { return tour(args[2], synth: args.count > 3 && args[3] == "synth") }
        if args.count >= 4, args[1] == "fuses" { return fuses(args[2], Array(args[3...])) }
        guard args.count >= 3, ["sheet", "gif", "moves"].contains(args[1]) else {
            return print("usage: render-fuse sheet|gif OUT, or render-fuse moves OUT NAME… (OUT without an extension)")
        }
        switch args[1] {
        case "sheet": png(FusePreviews(), args[2])
        case "gif": demo(args[2])
        default: moves(args[2], Array(args[3...]))
        }
    }

    @MainActor static func png(_ view: some View, _ path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        try! NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: path))
        print(path)
    }

    @MainActor static func moves(_ path: String, _ names: [String]) {
        let picked = names.compactMap { name in FusePreviews.moves.first { $0.0 == name } }
        guard picked.count == names.count, !names.isEmpty else {
            return print("moves: " + FusePreviews.moves.map { "\"\($0.0)\"" }.joined(separator: ", "))
        }
        png(VStack(alignment: .leading, spacing: 10) {
            ForEach(picked, id: \.0) { name, from, to, span in
                let scene = FusePreviews.scene(from, to), times = FusePreviews.frames(span)
                Text(name).font(.caption).foregroundStyle(.white)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(400), spacing: 4), count: 4), spacing: 4) {
                    ForEach(times, id: \.self) { t in FuseFrame(scene: scene, t: t, dark: true, zoom: 4, width: 100) }
                }
                HStack(spacing: 2) { ForEach(times, id: \.self) { t in FuseFrame(scene: scene, t: t, zoom: 1, width: 100) } }
            }
        }.padding(10).background(Color(white: 0.1)), path + ".png")
        // And at real speed, with a beat between moves.
        let fps = 50.0
        gif(path + ".gif", zoom: 4, width: 100, frames: picked.flatMap { _, from, to, span in
            let scene = FusePreviews.scene(from, to), n = Int(span * fps)
            return (0...n).map { (scene, Double($0) / fps, $0 == n ? 0.8 : 1 / fps) }
        })
    }

    @MainActor static func demo(_ path: String) {
        let fps = 25.0
        var timeline: [(at: Double, look: FuseLook)] = [], end = 0.0
        for (wait, look) in FusePreviews.demo { timeline.append((end, look)); end += wait }
        var scene = FuseScene(), next = 0, frames: [(FuseScene, Double, Double)] = []
        for f in 0..<Int(end * fps) {
            let t = Double(f) / fps
            while next < timeline.count, timeline[next].at <= t {
                scene.update(timeline[next].look, at: t, animated: next > 0)
                next += 1
            }
            frames.append((scene, t, 1 / fps))
        }
        gif(path, zoom: 3, width: 120, frames: frames)
    }

    /// A looping GIF of scenes on a dark and a light menu bar, each frame held for its delay.
    @MainActor static func gif(_ path: String, zoom: Double, width: Double, frames: [(scene: FuseScene, t: Double, delay: Double)]) {
        let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (scene, t, delay) in frames {
            let renderer = ImageRenderer(content: VStack(spacing: 0) {
                FuseFrame(scene: scene, t: t, dark: true, zoom: zoom, width: width)
                FuseFrame(scene: scene, t: t, dark: false, zoom: zoom, width: width)
            })
            CGImageDestinationAddImage(gif, renderer.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        CGImageDestinationFinalize(gif)
        print(path)
    }

    /// A README clip's recorded frames in FRAMES as they are, WIDTH px wide, in OUT, without macOS's recording dot.
    @MainActor static func plain(_ frames: String, _ out: String, _ width: Double) {
        let files = try! FileManager.default.contentsOfDirectory(atPath: frames).filter { $0.hasSuffix(".png") }.sorted()
        for (i, name) in files.enumerated() {
            let recorded = NSImage(contentsOfFile: frames + "/" + name)!
            let frame = NSImage(cgImage: withoutDot(recorded.cgImage(forProposedRect: nil, context: nil, hints: nil)!), size: recorded.size)
            let view = Image(nsImage: frame).resizable().interpolation(.high)
                .frame(width: width, height: (width * frame.size.height / frame.size.width).rounded())
            try! NSBitmapImageRep(cgImage: ImageRenderer(content: view).cgImage!).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: String(format: "%@/c%04d.png", out, i)))
        }
    }

    /// The README's landing: the recorded menu bar's frames in FRAMES, in OUT, without macOS's recording dot, with
    /// rounded corners, floating on a backdrop with a soft shadow under it: white for GitHub's light page, its dark
    /// card colour for its dark one, where a faint edge keeps the black bar apart from it. The shadow is short, a few
    /// greys, so a GIF's palette keeps it smooth.
    @MainActor static func bar(_ frames: String, _ out: String, dark: Bool) {
        let files = try! FileManager.default.contentsOfDirectory(atPath: frames).filter { $0.hasSuffix(".png") }.sorted()
        for (i, name) in files.enumerated() {
            let still = withoutDot(NSImage(contentsOfFile: frames + "/" + name)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            let view = floating(still, dark: dark)
                .padding(.horizontal, Double(still.height) * 0.7)
                .padding(.vertical, Double(still.height) * 0.6)
                .background(dark ? Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255) : .white) // #161b22, GitHub's dark card
            try! NSBitmapImageRep(cgImage: ImageRenderer(content: view).cgImage!).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: String(format: "%@/c%04d.png", out, i)))
        }
    }

    /// The menu bar, rounded, with its shadow, and on a dark backdrop a faint edge.
    static func floating(_ bar: CGImage, dark: Bool) -> some View {
        let h = Double(bar.height), corners = RoundedRectangle(cornerRadius: h * 0.28, style: .continuous)
        return Image(decorative: bar, scale: 1).resizable()
            .frame(width: Double(bar.width), height: h)
            .clipShape(corners)
            .overlay(corners.strokeBorder(Color.white.opacity(dark ? 0.16 : 0), lineWidth: 2))
            .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: h * 0.22, y: h * 0.1)
    }

    /// The repo's social preview, 1280 x 640, what a link to it shows: the name, what it is, and of the menu bar's frames
    /// in FRAMES the one with the most fire in it, on GitHub's dark page.
    @MainActor static func social(_ frames: String, _ out: String) {
        let bars = try! FileManager.default.contentsOfDirectory(atPath: frames).filter { $0.hasSuffix(".png") }.sorted()
            .map { withoutDot(NSImage(contentsOfFile: frames + "/" + $0)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!) }
        let bar = bars.max { fire($0) < fire($1) }!
        let view = VStack(spacing: 0) {
            Text("Lunte").font(.system(size: 132, weight: .bold)).foregroundStyle(.white)
            Text("Dynamite in your menu bar").font(.system(size: 46, weight: .semibold)).foregroundStyle(Color(white: 0.78))
                .padding(.top, 4)
            floating(bar, dark: true).padding(.top, 58)
            Text("Lit by how you talk to your agent").font(.system(size: 30, weight: .medium)).foregroundStyle(Color(white: 0.55))
                .padding(.top, 46)
        }
        .frame(width: 1280, height: 640)
        .background(Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)) // #0d1117, GitHub's dark page
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        try! NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
    }

    /// The app's icon in DIR, every size iconutil wants, each drawn at its own size: the menu bar's Lunte the moment a
    /// prompt lights it, when the flame is at its biggest, on a black squircle like a full-screen app's menu bar.
    static func icon(_ dir: String) {
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var scene = FuseScene()
        scene.update(FuseLook(), at: 0, animated: false)
        scene.update(FuseLook(left: 0.96, prompt: 1, bite: 0.04), at: 1)
        scene.still = true
        let coil = stride(from: 0.0, through: 0.96, by: 0.005).map { FuseScene.restingPoint($0, head: 0, tail: 0.96) }
        let tip = coil.last!, zoom = 20.0 // on a 1024 canvas
        let middle = CGPoint(x: (coil.map(\.x).min()! + max(coil.map(\.x).max()!, tip.x + 1.5)) / 2,
                             y: (coil.map(\.y).min()! + max(coil.map(\.y).max()!, tip.y + 3.5)) / 2) // with the flame
        let squircle = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: CGRect(x: 100, y: 100, width: 824, height: 824)).cgPath
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = points * scale, k = Double(px) / 1024
                let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.scaleBy(x: k, y: k)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.3)) // device space
                ctx.addPath(squircle)
                ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
                ctx.fillPath()
                ctx.restoreGState()
                ctx.saveGState()
                ctx.addPath(squircle)
                ctx.clip()
                let shade = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.03, alpha: 1)] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
                ctx.restoreGState()
                ctx.translateBy(x: 512 - middle.x * zoom, y: 512 - middle.y * zoom)
                ctx.scaleBy(x: zoom, y: zoom)
                scene.draw(ctx, at: 1.03, ink: CGColor(gray: 1, alpha: 0.92))
                try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: "\(dir)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
            }
        }
    }

    /// The Boom as the screen shows it, on a 960 x 600 pt corner of it with the fuse in the middle of the menu bar: a
    /// stand-in desktop with a window on it, the menu bar with the fuse in it, the drops falling from it, and the blast
    /// over all. Each kind races out, waits 2 s and blows; `close` is a close call that crawls, drips and climbs back
    /// out. Twelve moments in a sheet, OUT-NAME.png, and every frame at 50 fps in OUT-NAME/, for ffmpeg.
    @MainActor static func blast(_ path: String, _ args: [String]) {
        let renderer = BlastRenderer()!
        var picks: [(name: String, blast: BlastScene?)] = []
        for (i, a) in args.enumerated() where Double(a) == nil {
            if a == "close" { picks.append((a, nil)); continue }
            guard let kind = BlastScene.Kind(rawValue: a) else {
                return print("blast: close, " + BlastScene.Kind.allCases.map(\.rawValue).joined(separator: ", "))
            }
            let size = i + 1 < args.count ? Double(args[i + 1]) ?? 1 : 1
            picks.append((a, BlastScene(kind, size: size, seed: UInt64(i + 1))))
        }
        if picks.isEmpty { picks = BlastScene.Kind.allCases.map { ($0.rawValue, BlastScene($0)) } + [("close", nil)] }
        let size = CGSize(width: 960, height: 600), bar = 24.0
        let origin = CGPoint(x: 480 - FuseScene.start, y: size.height - bar + 3) // the fuse scene's, as FuseView has it
        let at = CGPoint(x: 480, y: origin.y + 9.5) // where the fuse starts, and blows
        for (name, blast) in picks {
            // What the menu bar fuse is told, and when; a Boom bangs after the race and 2 s of silence.
            let bang = 0.3 + FuseScene.raceFor + 2
            let script: [(Double, FuseLook)] = blast == nil
                ? [(0, FuseLook(left: 0.45)), (0.3, FuseLook(left: 0.08, prompt: 1, bite: 0.37)), (6.5, FuseLook(left: 0.55, prompt: 2))]
                : [(0, FuseLook(left: 0.3)), (0.3, FuseLook(phase: .fusing, left: 0)), (bang, FuseLook(phase: .blown))]
            let end = blast.map { b in bang + (0...).lazy.map { Double($0) / 50 }.first { BlastScene.time($0) >= b.over }! } ?? 9
            func scene(_ t: Double) -> FuseScene {
                var scene = FuseScene()
                for (i, (when, look)) in script.enumerated() where when <= t { scene.update(look, at: when, animated: i > 0) }
                return scene
            }
            func frame(_ t: Double, scale: Double) -> CGImage {
                let w = Int(size.width * scale), h = Int(size.height * scale)
                let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.scaleBy(x: scale, y: scale)
                desk(ctx, size, bar: bar)
                let fuse = scene(t)
                ctx.saveGState()
                ctx.translateBy(x: origin.x, y: origin.y)
                fuse.draw(ctx, at: t, ink: CGColor(gray: 1, alpha: 0.9))
                fuse.drawDrips(ctx, at: t)
                ctx.restoreGState()
                if let blast, t >= bang {
                    ctx.draw(renderer.image(blast, since: t - bang, at: at, size: size, scale: scale)!, in: CGRect(origin: .zero, size: size))
                }
                return ctx.makeImage()!
            }
            func save(_ image: CGImage, _ file: String) {
                try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
            }
            let moments = blast == nil ? [0.5, 1, 1.5, 2, 3, 4, 5, 6, 6.6, 7, 7.5, 8.5]
                : [0.9, 1.5, 1.8, 2.1, 2.6, 3.5, 3.95, 4.2, 4.5, 4.9, 5.5, 6.5]
            let sheet = CGContext(data: nil, width: 4 * 480 + 3 * 4, height: 3 * 300 + 2 * 4, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sheet.setFillColor(CGColor(gray: 0.05, alpha: 1))
            sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            for (i, t) in moments.enumerated() {
                sheet.draw(frame(t, scale: 0.5), in: CGRect(x: (i % 4) * 484, y: (2 - i / 4) * 304, width: 480, height: 300))
            }
            let file = "\(path)-\(name)"
            save(sheet.makeImage()!, file + ".png")
            try? FileManager.default.removeItem(atPath: file)
            try! FileManager.default.createDirectory(atPath: file, withIntermediateDirectories: true)
            for f in 0..<Int(end * 50) { save(frame(Double(f) / 50, scale: 1), String(format: "%@/f%04d.png", file, f)) }
            print(file)
        }
    }

    /// The stand-in screen: a wallpaper, a window with lines of text, and a menu bar `bar` points tall.
    static func desk(_ ctx: CGContext, _ size: CGSize, bar: Double) {
        let wallpaper = CGGradient(colorsSpace: nil, colors: [Palette.rgb(0.16, 0.27, 0.52), Palette.rgb(0.55, 0.36, 0.6)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(wallpaper, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)) // a window, with lines of text
        ctx.fill(CGRect(x: 120, y: 90, width: 520, height: 400))
        ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
        ctx.fill(CGRect(x: 120, y: 462, width: 520, height: 28))
        ctx.setFillColor(CGColor(gray: 0.72, alpha: 1))
        for y in stride(from: 420.0, to: 120, by: -22) { ctx.fill(CGRect(x: 144, y: y, width: 300 + 140 * sin(y), height: 7)) }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 0.92)) // the menu bar
        ctx.fill(CGRect(x: 0, y: size.height - bar, width: size.width, height: bar))
    }

    /// Every move and every sound in one session, to OUT.wav and OUT.mp4: the fuse burns, goes out, grows, crawls into
    /// its last third dripping and climbs back out, then burns right through, builds up, falls silent and blows, and a
    /// fresh fuse comes. The sounds play as the app plays them at Maximum and full volume: the flame's voice from the
    /// scene, through the same synth, the moves' cues pitched for the fuse they leave, and the bang out of the silence. Drawn on the stand-in screen, with the menu bar magnified in a corner
    /// and a caption for each move.
    @MainActor static func tour(_ path: String, synth: Bool = false) {
        let bang = 21.3 + FuseScene.raceFor + 2
        let script: [(Double, FuseLook, String?)] = [
            (0, FuseLook(), "A fresh fuse"),
            (0.6, FuseLook(prompt: 1, rating: true), "You send a prompt: a breeze while it's rated"),
            (1.4, FuseLook(left: 0.75, prompt: 1, bite: 0.25), "Heat: it burns"),
            (6, FuseLook(left: 0.75, prompt: 2, rating: true), nil),
            (6.8, FuseLook(left: 1.05, prompt: 2), "Cool: it grows back, lower"),
            (9, FuseLook(left: 1.05, prompt: 3, rating: true), nil),
            (9.8, FuseLook(left: 0.08, prompt: 3, bite: 0.97), "Heat into the last third: the same flame, hotter, higher, dripping"),
            (15, FuseLook(left: 0.08, prompt: 4, rating: true), nil),
            (15.8, FuseLook(left: 0.5, prompt: 4), "Cool, just in time: a close call"),
            (20.5, FuseLook(left: 0.5, prompt: 5, rating: true), nil),
            (21.3, FuseLook(phase: .fusing, left: 0), "Heat burns right through: it crawls, stalls, then races out"),
            (21.3 + FuseScene.raceFor + 0.1, FuseLook(phase: .fusing, left: 0), "Silence…"),
            (bang, FuseLook(phase: .blown), "Boom"),
            (bang + 5.6, FuseLook(), "A new session: a fresh fuse"),
        ]
        let flame = synth ? nil : FlameSynth.Recording(calm: URL(fileURLWithPath: "Resources/fuse.wav"))!
        session(synth ? path + "-synth" : path, script: script, bangs: [bang], end: bang + 8.1) { _ in flame }
    }

    /// Fuse sounds side by side, to OUT.wav and OUT.mp4: each of FILES, a loop, as the flame in the same short session,
    /// captioned with its number. A fresh fuse, a burn, then the Boom's crawl, stalls and run-out, the silence and the
    /// bang. No other sounds, so only the fuse differs.
    @MainActor static func fuses(_ path: String, _ files: [String]) {
        var script: [(Double, FuseLook, String?)] = [], bangs: [Double] = [], loops: [(Double, FlameSynth.Recording)] = []
        let each = 4.8 + FuseScene.raceFor + 2.2
        for (i, file) in files.enumerated() {
            let at = Double(i) * each, bang = at + 3.8 + FuseScene.raceFor + 1.2, prompt = Double(2 * i)
            script += [(at, FuseLook(), "Fuse \(i + 1)"), (at + 0.3, FuseLook(prompt: prompt, rating: true), nil),
                       (at + 1, FuseLook(left: 0.6, prompt: prompt, bite: 0.4), nil),
                       (at + 3.2, FuseLook(left: 0.6, prompt: prompt + 1, rating: true), nil),
                       (at + 3.8, FuseLook(phase: .fusing, left: 0), nil), (bang, FuseLook(phase: .blown), nil)]
            bangs.append(bang)
            let loop = FlameSynth.read(URL(fileURLWithPath: file))!
            loops.append((at, FlameSynth.Recording(calm: loop, hot: loop)))
        }
        session(path, script: script, bangs: bangs, end: Double(files.count) * each, withCues: false) { t in loops.last { $0.0 <= t }?.1 }
    }

    /// Plays SCRIPT, what the menu bar fuse is told and when, with a caption where there is one, to PATH.wav and
    /// PATH.mp4: the sounds as the app plays them at Maximum and full volume, the flame through `FlameSynth` with the
    /// recording `flame` gives for the moment (nil: the synth), each Boom in BANGS, and the moves' own sounds unless
    /// not `withCues`. Drawn on the stand-in screen, with the menu bar magnified in a corner.
    @MainActor static func session(_ path: String, script: [(Double, FuseLook, String?)], bangs: [Double], end: Double,
                                   withCues: Bool = true, flame: (Double) -> FlameSynth.Recording?) {
        let renderer = BlastRenderer()!, fps = 50.0
        let blast = BlastScene(.kaboom, seed: 7)
        func scene(_ t: Double) -> FuseScene {
            var scene = FuseScene()
            for (i, (when, look, _)) in script.enumerated() where when <= t { scene.update(look, at: when, animated: i > 0) }
            return scene
        }
        // What the app would play, at Maximum and full volume: the moves' cues, and the flame's voice frame by frame.
        var cues: [(Double, String, Double)] = [], voices: [FuseScene.Voice] = []
        var whole = FuseScene()
        for (i, (when, look, _)) in script.enumerated() {
            for c in whole.update(look, at: when, animated: i > 0) where withCues { cues.append((when, "\(c)", FuseScene.pitch(look.left))) }
        }
        let frames = Int(end * fps), captions = script.compactMap { e in e.2.map { (e.0, $0) } }
        for f in 0..<frames { let t = Double(f) / fps; voices.append(scene(t).voice(at: t)) }

        // The mix, at 44.1 kHz, each part at the app's own gain (`Bang.cap`, and Maximum's louder flame).
        let rate = 44100.0, n = Int(end * rate), cap: Float = 0.6
        var mix = [[Float]](repeating: [Float](repeating: 0, count: n), count: 2)
        func sound(_ name: String) -> (channels: [[Float]], rate: Double) {
            let file = try! AVAudioFile(forReading: URL(fileURLWithPath: "Resources/\(name).wav"))
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try! file.read(into: buffer)
            let channels = (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: Int(buffer.frameLength))) }
            return (channels.count == 1 ? [channels[0], channels[0]] : channels, buffer.format.sampleRate)
        }
        func add(_ name: String, at t: Double, pitch: Double, gain: Float) { // played faster and higher by `pitch`, as varispeed does
            let s = sound(name), step = pitch * s.rate / rate, boost: Float = s.channels[0] == s.channels[1] ? 1.414 : 1
            var at = 0.0, i = Int(t * rate)
            while i < n, Int(at) + 1 < s.channels[0].count {
                let k = Int(at), f = Float(at - Double(k))
                for c in 0..<2 { mix[c][i] += gain * boost * (s.channels[c][k] * (1 - f) + s.channels[c][k + 1] * f) }
                at += step
                i += 1
            }
        }
        for (t, name, pitch) in cues { add(name, at: t, pitch: pitch, gain: cap) }
        for bang in bangs { add("boom", at: bang, pitch: blast.pitch, gain: cap) }
        var synth = FlameSynth(rate: rate), chunk = [Float](repeating: 0, count: Int(rate / fps))
        synth.puff = FlameSynth.read(URL(fileURLWithPath: "Resources/puff.wav"))
        for (f, voice) in voices.enumerated() { // the flame, as `Flame` plays it: the race at the Boom's volume, the rest louder
            synth.recording = flame(Double(f) / fps)
            synth.voice = voice
            synth.render(chunk.count, gain: cap * (voice.race ? 1 : 1.4), into: &chunk)
            for (j, x) in chunk.enumerated() where f * chunk.count + j < n { mix[0][f * chunk.count + j] += x; mix[1][f * chunk.count + j] += x }
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        out.frameLength = AVAudioFrameCount(n)
        for c in 0..<2 { for i in 0..<n { out.floatChannelData![c][i] = max(-1, min(1, mix[c][i])) } }
        try! AVAudioFile(forWriting: URL(fileURLWithPath: path + ".wav"), settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]).write(from: out)

        // The picture, straight into ffmpeg with the mix.
        let size = CGSize(width: 960, height: 600), bar = 24.0, scale = 2.0, w = 1920, h = 1200
        let origin = CGPoint(x: 480 - FuseScene.start, y: size.height - bar + 3), blownAt = CGPoint(x: 480, y: origin.y + 9.5)
        let ffmpeg = Process(), pipe = Pipe()
        ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        ffmpeg.arguments = ["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(w)x\(h)", "-r", "50",
                            "-i", "-", "-i", path + ".wav", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-c:a", "aac",
                            "-b:a", "192k", "-shortest", path + ".mp4"]
        ffmpeg.standardInput = pipe
        try! ffmpeg.run()
        let inset = CGRect(x: 690, y: 36, width: 246, height: 102), zoom = 3.0 // the menu bar, magnified, bottom right
        for f in 0..<frames {
            let t = Double(f) / fps, now = scene(t)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            desk(ctx, size, bar: bar)
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            now.draw(ctx, at: t, ink: CGColor(gray: 1, alpha: 0.9))
            now.drawDrips(ctx, at: t)
            ctx.restoreGState()
            if let bang = bangs.last(where: { $0 <= t }), BlastScene.time(t - bang) < blast.over {
                ctx.draw(renderer.image(blast, since: t - bang, at: blownAt, size: size, scale: scale)!, in: CGRect(origin: .zero, size: size))
            }
            ctx.saveGState()
            let frame = CGPath(roundedRect: inset, cornerWidth: 10, cornerHeight: 10, transform: nil)
            ctx.addPath(frame)
            ctx.clip()
            ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
            ctx.fill(inset)
            ctx.translateBy(x: inset.midX + 34 * zoom, y: inset.maxY - 22 * zoom) // the item's right edge, the menu bar at the top
            ctx.scaleBy(x: zoom, y: zoom)
            now.draw(ctx, at: t, ink: CGColor(gray: 1, alpha: 0.9))
            now.drawDrips(ctx, at: t)
            ctx.restoreGState()
            ctx.addPath(frame)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
            ctx.setLineWidth(1)
            ctx.strokePath()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 6
            shadow.shadowColor = .black.withAlphaComponent(0.7)
            NSAttributedString(string: "Menu bar, \(Int(zoom))×", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.8), .shadow: shadow]).draw(at: CGPoint(x: inset.minX + 2, y: inset.maxY + 4))
            if let (since, text) = captions.last(where: { $0.0 <= t }) {
                NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(min(1, (t - since) / 0.2)), .shadow: shadow]).draw(at: CGPoint(x: 28, y: 40))
            }
            NSGraphicsContext.restoreGraphicsState()
            pipe.fileHandleForWriting.write(Data(bytes: ctx.data!, count: w * h * 4))
        }
        try! pipe.fileHandleForWriting.close()
        ffmpeg.waitUntilExit()
        print(path + ".mp4")
    }

    /// How many of the image's pixels are the flame's and the sparks' orange and yellow.
    static func fire(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 0, to: px.count, by: 4).filter { px[$0] > 190 && (70...215).contains(px[$0 + 1]) && px[$0 + 2] < 120 }.count
    }

    /// The frame without macOS's recording dot, the blue-violet one beside Control Center in the menu bar: found by its
    /// colour in the top 64 rows, and painted over with the menu bar just above it.
    static func withoutDot(_ image: CGImage) -> CGImage {
        let w = image.width, h = min(64, image.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let top = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        top.draw(image, in: CGRect(x: 0, y: h - image.height, width: w, height: image.height)) // its first rows, top down
        var dot = CGRect.null
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if px[i + 2] > 220, px[i] < 160, px[i + 1] < 150 { dot = dot.union(CGRect(x: x, y: y, width: 1, height: 1)) }
            }
        }
        guard !dot.isNull else { return image }
        dot = dot.insetBy(dx: -3, dy: -3)
        guard let above = image.cropping(to: dot.offsetBy(dx: 0, dy: -dot.height)) else { return image }
        let out = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        out.draw(above, in: CGRect(x: dot.minX, y: CGFloat(image.height) - dot.maxY, width: dot.width, height: dot.height))
        return out.makeImage()!
    }
}
