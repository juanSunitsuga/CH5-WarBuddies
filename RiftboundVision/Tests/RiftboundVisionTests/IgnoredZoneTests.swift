import Testing
import CoreGraphics
@testable import RiftboundVision

/// A card in the Trash has left play. Its arrival there, any shuffling
/// within the pile, and its eventual disappearance say nothing about what
/// a player is doing on the board, so `TemporalEventDetector` stops
/// reporting on it.
@Suite("Ignored Zones")
struct IgnoredZoneTests {
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

    private static func detection(at center: CGPoint) -> Detection {
        Detection(
            type: .card,
            center: center,
            boundingBox: CGRect(x: center.x - 40, y: center.y - 55, width: 80, height: 110),
            rotation: 0,
            confidence: 0.95,
            recognizedLabel: "Sneaky Deckhand"
        )
    }

    /// Drives enough polls to clear `confirmationFrames`, returning every
    /// event the detector chose to report.
    private static func events(at centers: [CGPoint], ignoredZones: Set<Zone>) -> [VisionEvent] {
        let tracker = ObjectTracker()
        let detector = TemporalEventDetector(ignoredZones: ignoredZones)
        let mapper = zoneMapper()

        var collected: [VisionEvent] = []
        for (index, center) in centers.enumerated() {
            let result = tracker.update(
                detections: [detection(at: center)],
                zoneMapper: mapper,
                frameIndex: index + 1,
                timestamp: Double(index) * 0.35,
                previousTimestamp: index == 0 ? nil : Double(index - 1) * 0.35
            )
            collected += detector.process(result, zoneMapper: mapper, timestamp: Double(index) * 0.35)
        }
        return collected
    }

    @Test("A card sitting in the Trash reports nothing")
    func trashIsSilent() {
        let events = Self.events(
            at: Array(repeating: Self.trashCenter, count: 4),
            ignoredZones: [.trash]
        )
        #expect(events.isEmpty)
    }

    @Test("Moving a card into the Trash isn't reported either")
    func movingIntoTrashIsSilent() {
        // Settle in Base, then move to Trash and settle there.
        let path = Array(repeating: Self.baseCenter, count: 3) + Array(repeating: Self.trashCenter, count: 4)
        let events = Self.events(at: path, ignoredZones: [.trash])

        #expect(events.allSatisfy { $0.currentZone != .trash })
        #expect(!events.contains { $0.type == .objectMoved && $0.currentZone == .trash })
    }

    /// The same path with nothing ignored must still produce the move —
    /// otherwise this suite would pass on a detector that reports nothing
    /// at all.
    @Test("Without the ignore rule, the same move to Trash is reported")
    func withoutIgnoreRuleTheMoveIsReported() {
        let path = Array(repeating: Self.baseCenter, count: 3) + Array(repeating: Self.trashCenter, count: 4)
        let events = Self.events(at: path, ignoredZones: [])

        #expect(events.contains { $0.type == .objectMoved && $0.currentZone == .trash })
    }

    @Test("Activity in a normal zone is still reported")
    func normalZonesStillReport() {
        let events = Self.events(
            at: Array(repeating: Self.baseCenter, count: 4),
            ignoredZones: [.trash]
        )
        #expect(events.contains { $0.type == .objectAppeared })
    }
}
