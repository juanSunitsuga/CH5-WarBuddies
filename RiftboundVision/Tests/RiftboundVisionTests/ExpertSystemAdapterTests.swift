import Testing
import CoreGraphics
@testable import RiftboundVision
import RiftboundExpertSystem

struct ExpertSystemAdapterTests {

    private func square(_ minX: CGFloat, _ minY: CGFloat, _ size: CGFloat = 50) -> [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: minX + size, y: minY), CGPoint(x: minX + size, y: minY + size), CGPoint(x: minX, y: minY + size)]
    }

    /// Playing a card (Hand → Battlefield) is the one physical signature
    /// `TableRegion`/`Location` can represent today — verifies the full
    /// VisionEvent → ObservedTableEvent translation end to end, and that
    /// the resulting event is exactly what `GameEngine.process` already
    /// consumes (no new protocol needed on the Expert System side).
    @Test("A confirmed Hand → Battlefield move becomes a cardMoved ObservedTableEvent")
    func handToBattlefieldBecomesObservedTableEvent() async {
        let playerA = PlayerID()
        let battlefieldID = BattlefieldID()
        let zoneMapper = ZoneMapper(zones: [
            BoardZone(type: .player1Hand, polygon: square(0, 0), owner: .player1),
            BoardZone(type: .battlefield, polygon: square(200, 200), battlefieldSlot: 0)
        ])
        let adapter = ExpertSystemAdapter(
            zoneMapper: zoneMapper,
            playerCalibration: [.player1: playerA],
            battlefieldCalibration: [0: battlefieldID],
            // See TemporalEventDetectorTests.Pipeline — generous match
            // distance since this test's zones are pixel-space apart on
            // purpose, and it's exercising zone-confirmation, not
            // identity-matching robustness.
            tracker: ObjectTracker(matchDistanceThreshold: 2000)
        )

        let stream = adapter.events()

        func card(at point: CGPoint) -> Detection {
            Detection(type: .card, center: point, boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30), rotation: 0, confidence: 0.95)
        }

        adapter.ingest(detections: [card(at: CGPoint(x: 25, y: 25))], frameIndex: 0, timestamp: 0)
        adapter.ingest(detections: [card(at: CGPoint(x: 25, y: 25))], frameIndex: 1, timestamp: 1.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 1000, y: 1000))], frameIndex: 2, timestamp: 2.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 1000, y: 1000))], frameIndex: 3, timestamp: 3.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 225, y: 225))], frameIndex: 4, timestamp: 4.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 225, y: 225))], frameIndex: 5, timestamp: 5.0 / 30)
        adapter.finish()

        var received: [ObservedTableEvent] = []
        for await event in stream { received.append(event) }

        let moved = received.compactMap { event -> (TableRegion, TableRegion)? in
            if case .cardMoved(let from, let to) = event.kind { return (from, to) }
            return nil
        }
        #expect(moved.count == 1)
        #expect(moved.first?.0.isHandRegion == true)
        #expect(moved.first?.1.location == .battlefield(battlefieldID))
        #expect(moved.first?.1.owner == playerA)
    }

    /// KNOWN GAP, verified rather than assumed: Main Deck / Rune Deck /
    /// Trash / Rune Area have no `TableRegion` representation yet, so a
    /// Draw (Main Deck → Hand) can't be forwarded — it should be dropped
    /// into `unrepresentableZoneEvents`, not silently invented as a wrong
    /// `TableRegion`.
    @Test("A Draw signature (Main Deck to Hand) is not forwarded, and is recorded as unrepresentable")
    func mainDeckToHandIsNotForwardable() async {
        let playerA = PlayerID()
        let zoneMapper = ZoneMapper(zones: [
            BoardZone(type: .mainDeck, polygon: square(400, 0), owner: .player1),
            BoardZone(type: .player1Hand, polygon: square(0, 0), owner: .player1)
        ])
        let adapter = ExpertSystemAdapter(
            zoneMapper: zoneMapper,
            playerCalibration: [.player1: playerA],
            tracker: ObjectTracker(matchDistanceThreshold: 2000)
        )

        let stream = adapter.events()

        func card(at point: CGPoint) -> Detection {
            Detection(type: .card, center: point, boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30), rotation: 0, confidence: 0.95)
        }

        adapter.ingest(detections: [card(at: CGPoint(x: 425, y: 25))], frameIndex: 0, timestamp: 0)
        adapter.ingest(detections: [card(at: CGPoint(x: 425, y: 25))], frameIndex: 1, timestamp: 1.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 25, y: 25))], frameIndex: 2, timestamp: 2.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 25, y: 25))], frameIndex: 3, timestamp: 3.0 / 30)
        adapter.finish()

        var received: [ObservedTableEvent] = []
        for await event in stream { received.append(event) }

        #expect(received.isEmpty)
        #expect(adapter.unrepresentableZoneEvents.contains { $0.previousZone == .mainDeck && $0.currentZone == .player1Hand })
    }
}
