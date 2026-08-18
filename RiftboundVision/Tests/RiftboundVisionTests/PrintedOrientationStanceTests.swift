import Testing
import CoreGraphics
@testable import RiftboundVision

/// A card's stance read against its *printed* orientation rather than its
/// bounding box alone.
@Suite("Printed Orientation Stance")
struct PrintedOrientationStanceTests {

    private func object(width: CGFloat, height: CGFloat) -> TrackedObject {
        TrackedObject(
            id: 1, type: .card, center: .zero,
            boundingBox: CGRect(x: 0, y: 0, width: width, height: height),
            rotation: 0, confidence: 0.9, isVisible: true, lastSeenFrame: 0
        )
    }

    private func printing(orientation: CardOrientation) -> CardPrinting {
        CardPrinting(
            id: "x", name: "Test", riftboundID: "test-001", collectorNumber: 1,
            attributes: .init(energy: nil, might: nil, power: nil),
            classification: .init(type: "Battlefield", supertype: nil, rarity: nil, domain: []),
            text: .init(plain: "", flavour: nil),
            set: .init(setID: "OGN", label: "Origins"),
            media: .init(imageURL: nil),
            orientation: orientation
        )
    }

    /// Every Battlefield in the bundled decks is printed landscape, so a
    /// wide bounding box is its *upright* shape. Judging by shape alone
    /// calls it exhausted the moment it's placed and never stops — which
    /// held the Awaken phase open forever, since that phase waits for
    /// nothing to be exhausted.
    @Test("A landscape card lying wide is ready, not exhausted")
    func landscapeCardLyingWideIsReady() {
        let wide = object(width: 100, height: 60)

        #expect(wide.stance == .exhausted, "Shape alone reads this as exhausted.")
        #expect(wide.stance(knowing: printing(orientation: .landscape)) == .ready)
    }

    @Test("A landscape card standing tall has been turned")
    func landscapeCardStandingTallIsExhausted() {
        let tall = object(width: 60, height: 100)

        #expect(tall.stance(knowing: printing(orientation: .landscape)) == .exhausted)
    }

    @Test("A portrait card is judged the same either way")
    func portraitCardAgreesWithShape() {
        let tall = object(width: 60, height: 100)
        let wide = object(width: 100, height: 60)

        #expect(tall.stance(knowing: printing(orientation: .portrait)) == .ready)
        #expect(wide.stance(knowing: printing(orientation: .portrait)) == .exhausted)
    }

    /// An unrecognized card has no printed orientation to consult, so the
    /// geometry-only answer is all there is — and stays the fallback rather
    /// than becoming an error.
    @Test("An unrecognized card falls back to its bounding box")
    func unknownCardFallsBackToShape() {
        #expect(object(width: 60, height: 100).stance(knowing: nil) == .ready)
    }
}
