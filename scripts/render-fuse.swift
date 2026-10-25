// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderFuse {
    @MainActor static func main() {
        let args = CommandLine.arguments
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
}
