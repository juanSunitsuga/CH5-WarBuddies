import Testing
import CoreGraphics
@testable import RiftboundVision

/// Playing a card physically means picking it up, carrying it (hidden by
/// your hand), and setting it down somewhere else — which moves it far
/// past `matchDistanceThreshold` between two detection polls. Distance
/// matching alone drops the track and starts a new one, so the move
/// surfaces as `.objectAppeared` with no origin, and an origin-less
/// appearance can't be translated into a Play. That made real plays
/// undetectable while sliding a card across the table worked fine.
///
/// The recognizer already knows *which card* each detection is, so these
/// pin the identity-based second matching pass that closes the gap.
@Suite("Identity Re-association")
struct IdentityReassociationTests {

    private static let handCenter = CGPoint(x: 300, y: 900)
    private static let battlefieldCenter = CGPoint(x: 300, y: 200)

    /// Hand spans the lower band, Battlefield the upper — far enough apart
    /// that a play is well beyond the 60pt distance gate.
    private static func mapper() -> ZoneMapper {
        ZoneMapper(zones: [
            BoardZone(
                type: .player1Hand,
                polygon: [CGPoint(x: 0, y: 700), CGPoint(x: 800, y: 700), CGPoint(x: 800, y: 1100), CGPoint(x: 0, y: 1100)],
                owner: .player1
            ),
            BoardZone(
                type: .battlefield,
                polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 0), CGPoint(x: 800, y: 400), CGPoint(x: 0, y: 400)],
                owner: nil,
                battlefieldSlot: 0
            )
        ])
    }

    private static func detection(at center: CGPoint, label: String?) -> Detection {
        Detection(
            type: .card,
            center: center,
            boundingBox: CGRect(x: center.x - 40, y: center.y - 55, width: 80, height: 110),
            rotation: 0,
            confidence: 0.95,
            recognizedLabel: label
        )
    }

    @Test("A card picked up from hand and placed on the battlefield keeps its track and reports the move")
    func pickedUpCardKeepsItsTrack() {
        let tracker = ObjectTracker()
        let zoneMapper = Self.mapper()

        // Frame 1: sitting in hand.
        let first = tracker.update(
            detections: [Self.detection(at: Self.handCenter, label: "Maddened Marauder")],
            zoneMapper: zoneMapper, frameIndex: 1, timestamp: 0, previousTimestamp: nil
        )
        let originalID = try? #require(first.objects.first?.id)
        #expect(first.objects.first?.currentZone == .player1Hand)

        // Frame 2: occluded by the player's hand — no detection at all.
        _ = tracker.update(
            detections: [], zoneMapper: zoneMapper, frameIndex: 2, timestamp: 0.35, previousTimestamp: 0
        )

        // Frame 3: set down on the battlefield, 700pt away — far outside
        // the distance gate, so only identity can rescue this.
        let third = tracker.update(
            detections: [Self.detection(at: Self.battlefieldCenter, label: "Maddened Marauder")],
            zoneMapper: zoneMapper, frameIndex: 3, timestamp: 0.7, previousTimestamp: 0.35
        )

        #expect(third.appearedIDs.isEmpty, "The card was re-associated, so it must not be reported as a new object.")
        let moved = third.objects.first
        #expect(moved?.id == originalID, "Same physical card must keep its tracked identity across the pickup.")
        #expect(moved?.previousZone == .player1Hand)
        #expect(moved?.currentZone == .battlefield)
    }

    @Test("A different card appearing far away is still a new object, not a re-association")
    func differentCardIsNotReassociated() {
        let tracker = ObjectTracker()
        let zoneMapper = Self.mapper()

        _ = tracker.update(
            detections: [Self.detection(at: Self.handCenter, label: "Maddened Marauder")],
            zoneMapper: zoneMapper, frameIndex: 1, timestamp: 0, previousTimestamp: nil
        )
        let second = tracker.update(
            detections: [Self.detection(at: Self.battlefieldCenter, label: "Sneaky Deckhand")],
            zoneMapper: zoneMapper, frameIndex: 2, timestamp: 0.35, previousTimestamp: 0
        )

        #expect(second.appearedIDs.count == 1, "A different card name must never adopt another card's track.")
    }

    /// `recognizedLabel` is a card *name*, not a per-copy identity, so two
    /// physical copies of the same card are indistinguishable by label
    /// alone. The nearest candidate wins, which keeps two copies sitting
    /// apart from swapping tracks.
    @Test("With two copies of one card, re-association takes the nearest")
    func duplicateCopiesTakeTheNearest() {
        let tracker = ObjectTracker()
        let zoneMapper = Self.mapper()

        let left = CGPoint(x: 150, y: 900)
        let right = CGPoint(x: 650, y: 900)
        let first = tracker.update(
            detections: [
                Self.detection(at: left, label: "Fury Rune"),
                Self.detection(at: right, label: "Fury Rune")
            ],
            zoneMapper: zoneMapper, frameIndex: 1, timestamp: 0, previousTimestamp: nil
        )
        let leftID = first.objects.first { $0.center == left }?.id
        let rightID = first.objects.first { $0.center == right }?.id
        #expect(leftID != rightID)

        // Both vanish, then both come back — swapped in array order, but in
        // the same physical spots. Order must not decide identity.
        _ = tracker.update(detections: [], zoneMapper: zoneMapper, frameIndex: 2, timestamp: 0.35, previousTimestamp: 0)
        let third = tracker.update(
            detections: [
                Self.detection(at: right, label: "Fury Rune"),
                Self.detection(at: left, label: "Fury Rune")
            ],
            zoneMapper: zoneMapper, frameIndex: 3, timestamp: 0.7, previousTimestamp: 0.35
        )

        #expect(third.appearedIDs.isEmpty)
        #expect(third.objects.first { $0.center == left }?.id == leftID)
        #expect(third.objects.first { $0.center == right }?.id == rightID)
    }
}
