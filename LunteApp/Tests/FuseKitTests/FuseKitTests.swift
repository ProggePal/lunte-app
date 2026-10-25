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
        ]
        for (i, look) in looks.enumerated() {
            scene.update(look, at: Double(i) * 0.2) // each lands mid-move of the last
            XCTAssertEqual(scene.length(100), look.left, accuracy: 1e-9, "after look \(i)")
        }
    }

    /// The item widens for the Boom's name at once, and narrows only once it has gone quiet.
    func testWidthWidensAtOnceAndNarrowsAfter() {
        var scene = FuseScene()
        scene.update(FuseLook(phase: .fusing, left: 0), at: 0, animated: false)
        scene.update(FuseLook(phase: .blown), at: 1)
        XCTAssertGreaterThan(scene.width(at: 1), FuseScene.fuseWidth)
        let loud = scene.width(at: 1)
        scene.update(FuseLook(phase: .blown, quiet: true), at: 10)
        XCTAssertEqual(scene.width(at: 10.5), loud)
        XCTAssertLessThan(scene.width(at: 20), loud)
    }
}
