import Testing
import CoreGraphics
@testable import RiftboundVision

/// A card in the Trash is out of play. Following it costs a tracking slot
/// for the rest of the game, and — worse — a pile the detector re-detects
/// every poll would mint a fresh ID each time, which is exactly the ID
/// churn tracking is supposed to avoid. So the Trash is listed, not
/// tracked.
@Suite("Discard Zones")
struct DiscardZoneTests {
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

    private static func detection(at center: CGPoint, label: String) -> Detection {
        Detection(
            type: .card,
            center: center,
            boundingBox: CGRect(x: center.x - 40, y: center.y - 55, width: 80, height: 110),
            rotation: 0,
            confidence: 0.95,
            recognizedLabel: label
        )
    }

    private static func run(_ path: [CGPoint], label: String = "Noxian Drummer", tracker: ObjectTracker = ObjectTracker()) -> ObjectTracker {
        let mapper = zoneMapper()
        for (index, center) in path.enumerated() {
            _ = tracker.update(
                detections: [detection(at: center, label: label)],
                zoneMapper: mapper,
                frameIndex: index + 1,
                timestamp: Double(index) * 0.12,
                previousTimestamp: index == 0 ? nil : Double(index - 1) * 0.12
            )
        }
        return tracker
    }

    @Test("A card that settles in the Trash is listed and stops being tracked")
    func settledCardIsDiscarded() {
        let tracker = Self.run(Array(repeating: Self.trashCenter, count: 5))

        #expect(tracker.discarded.count == 1)
        #expect(tracker.discarded.first?.label == "Noxian Drummer")
        #expect(tracker.discarded.first?.zone == .trash)
    }

    /// The pile is re-detected on every poll; each of those must not become
    /// a new track, or the Trash alone would burn an ID per poll.
    @Test("Re-detecting the same discarded card doesn't mint new IDs or duplicate rows")
    func repeatedDetectionsDoNotChurnIDs() {
        let tracker = Self.run(Array(repeating: Self.trashCenter, count: 40))

        #expect(tracker.discarded.count == 1, "One physical card should produce one row, however often it's re-detected.")
    }

    /// A card carried *over* the Trash on its way somewhere else must
    /// survive: discarding is confirmed over several polls, not on first
    /// sight.
    @Test("A card passing across the Trash isn't discarded")
    func passingOverTrashIsNotDiscarded() {
        // One poll in the trash zone, then settled back in Base.
        let path = Array(repeating: Self.baseCenter, count: 3)
            + [Self.trashCenter]
            + Array(repeating: Self.baseCenter, count: 4)
        let tracker = Self.run(path)

        #expect(tracker.discarded.isEmpty)
    }

    @Test("Cards outside a discard zone are tracked as normal")
    func normalZonesAreUnaffected() {
        let tracker = Self.run(Array(repeating: Self.baseCenter, count: 5))
        #expect(tracker.discarded.isEmpty)
    }

    /// Turning the rule off restores the old behaviour, which keeps this
    /// suite honest about what the rule is actually responsible for.
    @Test("With no discard zones configured, a Trash card is tracked like any other")
    func withoutDiscardZonesTrashIsTracked() {
        let tracker = Self.run(
            Array(repeating: Self.trashCenter, count: 5),
            tracker: ObjectTracker(discardZones: [])
        )
        #expect(tracker.discarded.isEmpty)
    }
}
