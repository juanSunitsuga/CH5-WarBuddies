import Testing
import CoreGraphics
@testable import RiftboundVision

/// `CoreMLCardDetector` gives axis-aligned boxes only, no true rotation
/// angle. `CardPrinting.isExhausted(observedBoundingBox:)` is what
/// recovers Exhaust/Ready (rules 592–593) from that: compare the box's
/// long axis against the card's own printed orientation.
struct CardOrientationTests {

    private func printing(orientation: CardOrientation) -> CardPrinting {
        CardPrinting(
            id: "test-id",
            name: "Test Card",
            riftboundID: "test-000-000",
            collectorNumber: nil,
            attributes: .init(energy: nil, might: nil, power: nil),
            classification: .init(type: "Unit", supertype: nil, rarity: nil, domain: []),
            text: .init(plain: "", flavour: nil),
            set: .init(setID: "TST", label: "Test Set"),
            media: .init(imageURL: nil),
            orientation: orientation
        )
    }

    @Test("A portrait card observed as a tall box is Ready (not exhausted)")
    func portraitCardTallBoxIsReady() {
        let card = printing(orientation: .portrait)
        let tallBox = CGRect(x: 0, y: 0, width: 60, height: 90)

        #expect(card.isExhausted(observedBoundingBox: tallBox) == false)
    }

    @Test("A portrait card observed as a wide box is Exhausted (rotated 90°)")
    func portraitCardWideBoxIsExhausted() {
        let card = printing(orientation: .portrait)
        let wideBox = CGRect(x: 0, y: 0, width: 90, height: 60)

        #expect(card.isExhausted(observedBoundingBox: wideBox) == true)
    }

    @Test("A landscape card (e.g. a Battlefield) observed as a wide box is Ready")
    func landscapeCardWideBoxIsReady() {
        let card = printing(orientation: .landscape)
        let wideBox = CGRect(x: 0, y: 0, width: 90, height: 60)

        #expect(card.isExhausted(observedBoundingBox: wideBox) == false)
    }

    @Test("A landscape card observed as a tall box is Exhausted (rotated 90°)")
    func landscapeCardTallBoxIsExhausted() {
        let card = printing(orientation: .landscape)
        let tallBox = CGRect(x: 0, y: 0, width: 60, height: 90)

        #expect(card.isExhausted(observedBoundingBox: tallBox) == true)
    }
}
