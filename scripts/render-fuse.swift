// Renders the menu bar fuse's previews to files, the same drawing the menu bar uses. Run with scripts/render-fuse.sh.
//   sheet OUT.png   every state and move, frame by frame (FusePreviews, the Xcode preview)
//   gif OUT.gif     the demo session at 3x on a dark and a light menu bar, 25 fps
//   moves OUT.png NAME…  the named moves from FusePreviews.moves, magnified, twelve moments each, then at actual size
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderFuse {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, ["sheet", "gif", "moves"].contains(args[1]) else {
            return print("usage: render-fuse sheet|gif OUT, or render-fuse moves OUT NAME…")
        }
        switch args[1] {
        case "sheet": png(FusePreviews(), args[2])
        case "gif": gif(args[2])
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
        }.padding(10).background(Color(white: 0.1)), path)
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
        print(path)
    }
}
