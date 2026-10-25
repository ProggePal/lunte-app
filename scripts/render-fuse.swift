// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
//   card FRAMES OUT WIDTH   a README clip's frames on a backdrop, for scripts/hero.sh
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderFuse {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 5, args[1] == "card" { return card(args[2], args[3], Double(args[4])!) }
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

    /// A README clip's recorded frames in FRAMES, WIDTH px wide, in OUT: each a card with rounded corners and a soft
    /// shadow, on a plain light backdrop with room around it, like a Loom or a tutorial, so the fuse gets the attention.
    @MainActor static func card(_ frames: String, _ out: String, _ width: Double) {
        let files = try! FileManager.default.contentsOfDirectory(atPath: frames).filter { $0.hasSuffix(".png") }.sorted()
        let pad = (width * 0.06).rounded(), inner = width - 2 * pad
        let corners = RoundedRectangle(cornerRadius: 12 * width / 800, style: .continuous)
        for (i, name) in files.enumerated() {
            let recorded = NSImage(contentsOfFile: frames + "/" + name)!
            let frame = NSImage(cgImage: withoutDot(recorded.cgImage(forProposedRect: nil, context: nil, hints: nil)!), size: recorded.size)
            let card = Image(nsImage: frame).resizable().interpolation(.high)
                .frame(width: inner, height: (inner * frame.size.height / frame.size.width).rounded())
                .clipShape(corners)
                .overlay(corners.strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 20 * width / 800, y: 10 * width / 800)
                .padding(pad)
                .background(Color(white: 0.965))
            try! NSBitmapImageRep(cgImage: ImageRenderer(content: card).cgImage!).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: String(format: "%@/c%04d.png", out, i)))
        }
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
