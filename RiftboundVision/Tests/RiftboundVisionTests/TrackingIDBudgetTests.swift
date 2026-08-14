import Testing
import CoreGraphics
@testable import RiftboundVision

/// Observed on a real table: tracking IDs reached roughly 1,400 while only
/// a handful of cards were in play. Two causes, both pinned here.
@Suite("Tracking ID Budget")
struct TrackingIDBudgetTests {
    private static let baseCenter = CGPoint(x: 200, y: 200)
    private static let trashCenter = CGPoint(x: 700, y: 200)

    private static func zoneMapper() -> ZoneMapper {
        ZoneMapper(zones: [
            BoardZone(
                type: .base,
                polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0), CGPoint(x: 400, y: 400), CGPoint(x: 0, y: 400)],
                owner: .player1
            ),
            BoardZone(
                type: .trash,
                polygon: [CGPoint(x: 500, y: 0), CGPoint(x: 900, y: 0), CGPoint(x: 900, y: 400), CGPoint(x: 500, y: 400)],
                owner: .player1
            )
        ])
    }

    private static func detection(at center: CGPoint, size: CGFloat = 110, label: String) -> Detection {
        Detection(
            type: .card,
            center: center,
            boundingBox: CGRect(x: center.x - size * 0.36, y: center.y - size / 2, width: size * 0.72, height: size),
            rotation: 0,
            confidence: 0.95,
            recognizedLabel: label
        )
    }

    /// A card sitting in the Trash is re-detected on every poll. Deciding
    /// to discard it *before* allocating an ID is what stops the pile
    /// consuming the whole ID space.
    @Test("A card parked in the Trash consumes no tracking IDs at all")
    func trashConsumesNoIDs() {
        let tracker = ObjectTracker()
        let mapper = Self.zoneMapper()

        for frame in 1...200 {
            _ = tracker.update(
                detections: [Self.detection(at: Self.trashCenter, label: "Noxian Drummer")],
                zoneMapper: mapper, frameIndex: frame,
                timestamp: Double(frame) * 0.1,
                previousTimestamp: frame == 1 ? nil : Double(frame - 1) * 0.1
            )
        }

        // One real card enters play afterwards; it must get a low number,
        // proving the 200 Trash polls burned nothing.
        let result = tracker.update(
            detections: [Self.detection(at: Self.baseCenter, label: "Sai Scout")],
            zoneMapper: mapper, frameIndex: 201, timestamp: 20.1, previousTimestamp: 20.0
        )
        let id = result.objects.first?.id
        #expect(id != nil)
        #expect((id ?? .max) < 5, "200 polls of a Trash card must not advance the ID counter.")
    }

    /// A fixed 60pt gate is generous at 720p and less than half a card at
    /// 4K, where it rejects obvious matches and forces a new track every
    /// poll. Scaling the radius to the card keeps behaviour identical at
    /// any resolution.
    @Test("A large card moving less than its own length keeps its ID")
    func largeCardKeepsIDWhenMovingLessThanItsOwnLength() {
        let tracker = ObjectTracker()
        let mapper = Self.zoneMapper()
        // 4K-scale card: 300pt tall, moving 120pt per poll — twice the old
        // fixed threshold, but well under half a card.
        let first = tracker.update(
            detections: [Self.detection(at: CGPoint(x: 100, y: 200), size: 300, label: "Sai Scout")],
            zoneMapper: mapper, frameIndex: 1, timestamp: 0, previousTimestamp: nil
        )
        let originalID = first.objects.first?.id

        let second = tracker.update(
            detections: [Self.detection(at: CGPoint(x: 220, y: 200), size: 300, label: "Sai Scout")],
            zoneMapper: mapper, frameIndex: 2, timestamp: 0.1, previousTimestamp: 0
        )

        #expect(second.appearedIDs.isEmpty, "A card moving less than its own length is the same card.")
        #expect(second.objects.first?.id == originalID)
    }

    /// The counterpart: two small cards a clear gap apart must not be
    /// merged just because the radius scales.
    @Test("A small card teleporting far still becomes a new track")
    func smallCardJumpingFarIsANewTrack() {
        let tracker = ObjectTracker()
        let mapper = Self.zoneMapper()
        _ = tracker.update(
            detections: [Self.detection(at: CGPoint(x: 60, y: 60), size: 60, label: "Sai Scout")],
            zoneMapper: mapper, frameIndex: 1, timestamp: 0, previousTimestamp: nil
        )
        // A different card name, far away — neither distance nor identity
        // should link them.
        let second = tracker.update(
            detections: [Self.detection(at: CGPoint(x: 380, y: 380), size: 60, label: "Petty Officer")],
            zoneMapper: mapper, frameIndex: 2, timestamp: 0.1, previousTimestamp: 0
        )
        #expect(second.appearedIDs.count == 1)
    }

    /// The steady state this is all for: cards sitting still across many
    /// polls must never advance the counter.
    @Test("Five cards held still for 100 polls use five IDs")
    func steadyTableUsesOneIDPerCard() {
        let tracker = ObjectTracker()
        let mapper = Self.zoneMapper()
        let names = ["Sai Scout", "Petty Officer", "Order Rune", "Void Gate", "Tibbers"]
        let spots = [CGPoint(x: 60, y: 60), CGPoint(x: 160, y: 60), CGPoint(x: 260, y: 60),
                     CGPoint(x: 60, y: 300), CGPoint(x: 160, y: 300)]

        var last: TrackerUpdateResult?
        for frame in 1...100 {
            last = tracker.update(
                detections: zip(spots, names).map { Self.detection(at: $0.0, size: 80, label: $0.1) },
                zoneMapper: mapper, frameIndex: frame,
                timestamp: Double(frame) * 0.1,
                previousTimestamp: frame == 1 ? nil : Double(frame - 1) * 0.1
            )
        }

        #expect(last?.objects.count == 5)
        #expect((last?.objects.map(\.id).max() ?? .max) <= 5, "IDs must not creep while nothing moves.")
    }
}
