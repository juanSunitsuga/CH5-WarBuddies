import Testing
import CoreGraphics
@testable import RiftboundVision

struct CardOrientationTests {

    @Test("A taller-than-wide box reads as Ready (upright)")
    func tallBoxIsReady() {
        let box = CGRect(x: 0, y: 0, width: 20, height: 30)
        #expect(box.cardOrientation == .ready)
    }

    @Test("A wider-than-tall box reads as Exhausted (tapped)")
    func wideBoxIsExhausted() {
        let box = CGRect(x: 0, y: 0, width: 30, height: 20)
        #expect(box.cardOrientation == .exhausted)
    }

    /// A near-square box (within the deadzone) must not commit to Exhausted
    /// — that's the transient mid-rotation frame the tolerance guards against.
    @Test("A near-square box stays Ready rather than flickering to Exhausted")
    func nearSquareStaysReady() {
        // 20 vs 20.5: |Δ| = 0.5, deadzone = 20.5 * 0.05 ≈ 1.025 → inside.
        let almostSquareWide = CGRect(x: 0, y: 0, width: 20.5, height: 20)
        #expect(almostSquareWide.cardOrientation == .ready)
    }

    @Test("A clearly wide box past the deadzone still reads Exhausted")
    func wideBoxOutsideDeadzone() {
        let box = CGRect(x: 0, y: 0, width: 25, height: 20)
        #expect(box.cardOrientation == .exhausted)
    }

    @Test("An empty box degrades to Ready rather than dividing by zero")
    func emptyBoxIsReady() {
        #expect(CGRect.zero.cardOrientation == .ready)
    }

    @Test("IoU of a rect with itself is 1")
    func iouIdentity() {
        let box = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(abs(box.intersectionOverUnion(box) - 1.0) < 0.0001)
    }

    @Test("IoU of disjoint rects is 0")
    func iouDisjoint() {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 100, y: 100, width: 10, height: 10)
        #expect(a.intersectionOverUnion(b) == 0)
    }

    @Test("IoU of half-overlapping equal rects is 1/3")
    func iouPartial() {
        // Two 10×10 rects offset by 5 in x → intersection 5×10=50,
        // union 100+100-50 = 150 → 50/150 = 0.333…
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 5, y: 0, width: 10, height: 10)
        #expect(abs(a.intersectionOverUnion(b) - 1.0 / 3.0) < 0.0001)
    }
}
