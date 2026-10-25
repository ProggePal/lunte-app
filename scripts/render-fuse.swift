// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
//   moves OUT NAME…  the named moves from FusePreviews.moves: OUT.png magnified, twelve moments each, then at actual
//                    size; OUT.gif magnified at real speed, 50 fps, one after the other
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderFuse {
    @MainActor static func main() {
        let args = CommandLine.arguments
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
}
