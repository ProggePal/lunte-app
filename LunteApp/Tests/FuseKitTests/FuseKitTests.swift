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

    /// The item widens for the Boom's words at once, never narrows while blown, and narrows after the fresh fuse is in.
    func testWidthOnlyNarrowsAfterTheBoom() {
        var scene = FuseScene()
        scene.update(FuseLook(phase: .fusing, left: 0), at: 0, animated: false)
        scene.update(FuseLook(phase: .blown, name: "Chain reaction", tier: 2), at: 1)
        let wide = scene.width(at: 1)
        XCTAssertGreaterThan(wide, FuseScene.fuseWidth)
        scene.update(FuseLook(phase: .blown, name: "Chain reaction", tier: 2, quiet: true), at: 10) // "Cooled off" is shorter
        XCTAssertEqual(scene.width(at: 600), wide)
        scene.update(FuseLook(), at: 700)
        XCTAssertEqual(scene.width(at: 700.5), wide)
        XCTAssertEqual(scene.width(at: 705), FuseScene.fuseWidth)
    }
}
