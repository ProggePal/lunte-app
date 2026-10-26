@testable import FuseKit
import XCTest

final class FuseKitTests: XCTestCase {
    /// Burns at the tip and cool fed in at the start, one at a time or from one prompt, always settle on what's left.
    func testFuseSettlesOnWhatsLeft() {
        var scene = FuseScene()
        scene.update(FuseLook(), at: 0, animated: false)
        let looks = [
            FuseLook(left: 0.6, prompt: 1, bite: 0.4),  // a burn
            FuseLook(left: 0.75, prompt: 2),            // cool
            FuseLook(left: 0.55, prompt: 3, bite: 0.5), // both: burns 0.5, feeds in 0.3
            FuseLook(left: 0.7),                        // a burn cooled off
            FuseLook(left: 0.3, prompt: 4, bite: 0.4),
            FuseLook(left: 1, prompt: 5),               // back to whole
            FuseLook(left: 1, prompt: 6, rating: true), // being rated: nothing yet
            FuseLook(left: 0.8, prompt: 6, bite: 0.3),  // rated: burns 0.3, feeds in 0.1
            FuseLook(left: 1.2, prompt: 7),             // cool grows it past a fresh fuse
            FuseLook(left: 1.05, prompt: 8, bite: 0.15), // and heat burns it back
        ]
        for (i, look) in looks.enumerated() {
            scene.update(look, at: Double(i) * 0.2) // each lands mid-move of the last
            XCTAssertEqual(scene.length(100), look.left, accuracy: 1e-9, "after look \(i)")
        }
    }

    /// The bang jolts what's in the menu bar while there's something to see, and has settled by the time the word lands.
    func testTheBangJolts() {
        var scene = FuseScene()
        scene.update(FuseLook(phase: .fusing, left: 0), at: 0, animated: false)
        scene.update(FuseLook(phase: .blown), at: 10)
        let jolts = stride(from: 10.0, to: 11, by: 0.01).map { abs(scene.jolt(at: $0)) }
        XCTAssertGreaterThan(jolts.max()!, 1)
        XCTAssertLessThan(abs(scene.jolt(at: 10 + FuseScene.calmAfter)), 0.01)
    }

    /// The jolt reaches the pixels: the bang's white-hot flash moves sideways with it, and only by it.
    func testTheFlashMovesWithTheJolt() {
        var scene = FuseScene()
        scene.update(FuseLook(phase: .fusing, left: 0), at: 0, animated: false)
        scene.update(FuseLook(phase: .blown), at: 10)
        let still = Self.whiteHot(scene, at: 10) // the jolt starts at 0
        var swing = 0.0
        for t in stride(from: 10.0, through: 10.3, by: 0.01) { // while the flash is the whitest thing there
            let moved = Self.whiteHot(scene, at: t) - still
            XCTAssertEqual(moved, scene.jolt(at: t), accuracy: 0.15, "at \(t)")
            swing = max(swing, abs(moved))
        }
        XCTAssertGreaterThan(swing, 1)
    }

    /// Where the white-hot middle of the drawing is, sideways, in points: drawn 8x, weighted by how white each pixel is.
    static func whiteHot(_ scene: FuseScene, at t: Double) -> Double {
        let zoom = 8, w = 48, h = 24
        let ctx = CGContext(data: nil, width: w * zoom, height: h * zoom, bitsPerComponent: 8, bytesPerRow: w * zoom * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(zoom), y: CGFloat(zoom))
        ctx.translateBy(x: CGFloat(w - 4), y: 3)
        scene.draw(ctx, at: t)
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0, weight = 0.0
        for i in 0..<(w * zoom * h * zoom) {
            let white = max(0, Double(min(px[4 * i], px[4 * i + 1], px[4 * i + 2])) / 255 - 0.5) // the flash, not the sparks
            sum += white * Double(i % (w * zoom))
            weight += white
        }
        return sum / weight / Double(zoom)
    }

    /// The item widens for the Boom's words at once, never narrows while blown, and narrows after the fresh fuse is in.
    func testWidthOnlyNarrowsAfterTheBoom() {
        var scene = FuseScene()
        scene.update(FuseLook(phase: .fusing, left: 0), at: 0, animated: false)
        scene.update(FuseLook(phase: .blown, name: "Chain reaction", tier: 2), at: 1)
        let wide = scene.width(at: 1)
        XCTAssertGreaterThan(wide, FuseScene.fuseWidth)
        scene.update(FuseLook(phase: .blown, name: "Chain reaction", tier: 2, quiet: true), at: 10) // "Calmed down" is shorter
        XCTAssertEqual(scene.width(at: 600), wide)
        scene.update(FuseLook(), at: 700)
        XCTAssertEqual(scene.width(at: 700.5), wide)
        XCTAssertEqual(scene.width(at: 705), FuseScene.fuseWidth)
    }
}
