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

    /// Cool and a fresh fuse have sounds of their own; launching, being rated and a prompt that does nothing stay
    /// silent, and the flame speaks through its voice, not a cue.
    // Why: the Boom is the only sound unless you ask (docs/why.md#fuse-sounds-opt-in)
    func testOnlyMovesMakeASound() {
        var scene = FuseScene()
        XCTAssertEqual(scene.update(FuseLook(left: 0.8), at: 0, animated: false), [])
        XCTAssertEqual(scene.update(FuseLook(left: 0.8, prompt: 1, rating: true), at: 1), [])
        XCTAssertEqual(scene.update(FuseLook(left: 0.8, prompt: 1), at: 2), []) // rated: nothing
        XCTAssertEqual(scene.update(FuseLook(left: 0.5, prompt: 2, bite: 0.3), at: 3), [])
        XCTAssertEqual(scene.update(FuseLook(left: 0.7, prompt: 3), at: 4), [.grow])
        XCTAssertEqual(scene.update(FuseLook(left: 0.6, prompt: 4, bite: 0.3), at: 5), [.grow])
        XCTAssertEqual(scene.update(FuseLook(phase: .fusing, left: 0), at: 6), [])
        XCTAssertEqual(scene.update(FuseLook(phase: .blown), at: 10), [])
        XCTAssertEqual(scene.update(FuseLook(), at: 20), [.fresh])
    }

    /// One voice for the flame: it catches with a flare, sizzles as the tip burns along and falls silent when it stalls,
    /// louder and higher in the last third, and ends in a short puff. The Boom's race crawls the same way, ends loudest,
    /// and cuts out into silence before the bang.
    // Why: one voice for the flame, and the suspense before the bang (docs/why.md#fuse-sounds-opt-in)
    func testTheFlameHasOneVoice() {
        var calm = FuseScene(), close = FuseScene()
        calm.update(FuseLook(left: 1), at: 0, animated: false)
        XCTAssertEqual(calm.voice(at: 0.5), FuseScene.Voice(pitch: FuseScene.pitch(1))) // unlit: nothing
        calm.update(FuseLook(left: 0.8, prompt: 1, bite: 0.2), at: 1)
        close.update(FuseLook(left: 0.5), at: 0, animated: false)
        close.update(FuseLook(left: 0.1, prompt: 1, bite: 0.4), at: 1)
        XCTAssertGreaterThan(calm.voice(at: 1.05).sizzle, calm.voice(at: 2.5).sizzle) // it catches, then burns on, quietly
        let crawl = stride(from: 2.0, to: 5, by: 0.02).map { close.voice(at: $0) }
        XCTAssertGreaterThan(crawl.map(\.sizzle).max()!, 2.5 * calm.voice(at: 1.5).sizzle) // the last third is far louder
        XCTAssertLessThan(crawl.map(\.sizzle).min()!, 0.1) // and falls silent when it stalls
        XCTAssertGreaterThan(crawl.map(\.pitch).max()!, calm.voice(at: 1.5).pitch) // and it's higher
        let out = stride(from: 2.0, to: 12, by: 0.01).map { calm.voice(at: $0) }
        XCTAssertEqual(out.last, FuseScene.Voice(pitch: FuseScene.pitch(0.8))) // gone, once it has puffed
        XCTAssertEqual(out.filter { $0.smoke > 0.05 }.count, 15, accuracy: 10) // in a puff of about a tenth of a second

        var race = FuseScene()
        race.update(FuseLook(left: 0.3), at: 0, animated: false)
        race.update(FuseLook(phase: .fusing, left: 0), at: 1)
        let build = stride(from: 1.05, to: 1 + FuseScene.raceFor - 0.02, by: 0.02).map { race.voice(at: $0) }
        XCTAssertTrue(build.allSatisfy(\.race))
        XCTAssertLessThan(build.map(\.sizzle).min()!, 0.1) // it stalls like a close call
        XCTAssertEqual(build.map(\.sizzle).max(), build.suffix(10).map(\.sizzle).max()) // and is loudest at the very end
        let silence = stride(from: 1 + FuseScene.raceFor + 1, to: 1 + FuseScene.raceFor + 3, by: 0.1).map { race.voice(at: $0) }
        XCTAssertTrue(silence.allSatisfy { $0.sizzle == 0 && $0.smoke < 0.05 }) // then silence

        // Like a string: the shorter the fuse, the higher, never past 1.8.
        XCTAssertEqual(FuseScene.pitch(1), 1, accuracy: 1e-9)
        XCTAssertLessThan(FuseScene.pitch(FuseScene.full), 1)
        XCTAssertGreaterThan(FuseScene.pitch(1.0 / 3), FuseScene.pitch(0.5))
        XCTAssertEqual(FuseScene.pitch(0), 1.8, accuracy: 1e-9)
    }

    /// A recorded flame plays its calm loop on a long fuse and its hot one near the end, the catch once as a burn flares
    /// and the puff once as it goes out.
    func testARecordedFlameFollowsTheVoice() {
        var synth = FlameSynth(rate: 1000)
        synth.recording = .init(catching: Array(repeating: 1, count: 50), calm: [0.1, 0.1], hot: [0.5, 0.5])
        synth.puff = Array(repeating: 2, count: 50)
        var out = [Float](repeating: 0, count: 500)
        func play(_ voice: FuseScene.Voice) -> [Float] { synth.voice = voice; synth.render(out.count, gain: 1, into: &out); return out }
        XCTAssertEqual(play(FuseScene.Voice(sizzle: 1, crackle: 0.1)).last!, 0.1, accuracy: 0.01) // calm, once it has glided up
        XCTAssertEqual(play(FuseScene.Voice(sizzle: 1, crackle: 0.9)).last!, 0.5, accuracy: 0.01) // hot near the end
        let caught = play(FuseScene.Voice(sizzle: 1, crackle: 0.9, flare: 1))
        XCTAssertGreaterThan(caught.first!, 1) // the catch rides on top
        XCTAssertEqual(play(FuseScene.Voice(sizzle: 1, crackle: 0.9, flare: 1)).first!, 0.5, accuracy: 0.01) // once
        XCTAssertGreaterThan(play(FuseScene.Voice(crackle: 0.9, smoke: 1)).first!, 1.5) // the puff
        XCTAssertEqual(play(FuseScene.Voice(crackle: 0.9, smoke: 1)).first!, 0, accuracy: 0.01) // once, then quiet
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
