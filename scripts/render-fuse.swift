// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
//   moves OUT NAME…  the named moves from FusePreviews.moves: OUT.png magnified, twelve moments each, then at actual
//                    size; OUT.gif magnified at real speed, 50 fps, one after the other
//   plain FRAMES OUT WIDTH   a README clip's frames as they are, for scripts/hero.sh
//   bar FRAMES OUT light|dark   the README's menu bar frames, rounded, on a backdrop, for scripts/hero.sh
//   social FRAMES OUT.png   the repo's social preview, for scripts/hero.sh
//   icon OUT.iconset   the app's icon at every size, for iconutil
import AppKit
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
