// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
//   plain FRAMES OUT WIDTH   a README clip's frames as they are, for scripts/hero.sh
//   bar FRAMES OUT light|dark   the README's menu bar frames, rounded, on a backdrop, for scripts/hero.sh
//   social FRAMES OUT.png   the repo's social preview, for scripts/hero.sh
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
        guard args.count == 3, ["sheet", "gif"].contains(args[1]) else { return print("usage: render-fuse sheet|gif OUT") }
        args[1] == "sheet" ? sheet(args[2]) : gif(args[2])
        print(args[2])
    }

    @MainActor static func sheet(_ path: String) {
        let renderer = ImageRenderer(content: FusePreviews())
        renderer.scale = 2
        try! NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: path))
    }

    @MainActor static func gif(_ path: String) {
        let fps = 25.0
        var timeline: [(at: Double, look: FuseLook)] = [], end = 0.0
        for (wait, look) in FusePreviews.demo { timeline.append((end, look)); end += wait }
        let frames = Int(end * fps)
        let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var scene = FuseScene(), next = 0
        for f in 0..<frames {
            let t = Double(f) / fps
            while next < timeline.count, timeline[next].at <= t {
                scene.update(timeline[next].look, at: t, animated: next > 0)
                next += 1
            }
            let renderer = ImageRenderer(content: VStack(spacing: 0) { [scene] in
                FuseFrame(scene: scene, t: t, dark: true, zoom: 3, width: 120)
                FuseFrame(scene: scene, t: t, dark: false, zoom: 3, width: 120)
            })
            CGImageDestinationAddImage(gif, renderer.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
        }
        CGImageDestinationFinalize(gif)
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
