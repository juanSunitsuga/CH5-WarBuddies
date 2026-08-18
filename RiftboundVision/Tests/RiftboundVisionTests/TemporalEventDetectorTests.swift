import Testing
import CoreGraphics
import Foundation
@testable import RiftboundVision

private func square(_ minX: CGFloat, _ minY: CGFloat, _ size: CGFloat = 50) -> [CGPoint] {
    [CGPoint(x: minX, y: minY), CGPoint(x: minX + size, y: minY), CGPoint(x: minX + size, y: minY + size), CGPoint(x: minX, y: minY + size)]
}

/// Mirrors the brief's calibrated table: a hand, one battlefield, a rune
/// deck, and a rune area, each a disjoint calibrated rectangle, plus a
/// point far outside all of them standing in for "in transit / occluded"
/// (`.unknown`).
private let testZones = ZoneMapper(zones: [
    BoardZone(type: .player1Hand, polygon: square(0, 0)),
    BoardZone(type: .battlefield, polygon: square(200, 200), battlefieldSlot: 0),
    BoardZone(type: .runeDeck, polygon: square(400, 0)),
    BoardZone(type: .runeArea, polygon: square(400, 200)),
])
private let unknownPoint = CGPoint(x: 1000, y: 1000)
private let handPoint = CGPoint(x: 25, y: 25)
private let battlefieldPoint = CGPoint(x: 225, y: 225)
private let runeDeckPoint = CGPoint(x: 425, y: 25)
private let runeAreaPoint = CGPoint(x: 425, y: 225)

private struct Pipeline {
    // A generous match distance: these tests exercise zone-transition
    // *confirmation* (TemporalEventDetector), not identity-matching
    // robustness at realistic camera distances (already covered by
    // `ObjectTrackerTests`) — the calibrated zones here are pixel-space
    // apart on purpose so each is unambiguous.
    let tracker = ObjectTracker(matchDistanceThreshold: 2000)
    let detector = TemporalEventDetector()
    var frame = 0
    var timestamp: TimeInterval = 0

    mutating func step(_ point: CGPoint, type: ObjectType = .card, rotation: CGFloat = 0, present: Bool = true) -> [VisionEvent] {
        // `TemporalEventDetector` now derives rotation from `TrackedObject
        // .stance` (bounding-box aspect ratio — see `CGRect.cardStance`),
        // not from `Detection.rotation` directly (`CoreMLCardDetector`
        // never reports a real angle). A non-zero `rotation` here has to
        // produce a wide (Exhausted-shaped) box, or `.stance` stays
        // `.ready` regardless of what `rotation` says, and no
        // `.objectRotated` event ever fires. Ready's box is unchanged
        // (20×30, same as before this existed) so every other test that
        // doesn't pass `rotation` is unaffected.
        let isExhausted = rotation != 0
        let boxWidth: CGFloat = isExhausted ? 30 : 20
        let boxHeight: CGFloat = isExhausted ? 20 : 30
        let detections = present ? [Detection(type: type, center: point, boundingBox: CGRect(x: point.x - boxWidth / 2, y: point.y - boxHeight / 2, width: boxWidth, height: boxHeight), rotation: rotation, confidence: 0.95)] : []
        let previous = frame == 0 ? nil : timestamp
        frame += 1
        timestamp = Double(frame) / 30
        let result = tracker.update(detections: detections, zoneMapper: testZones, frameIndex: frame, timestamp: timestamp, previousTimestamp: previous)
        return detector.process(result, zoneMapper: testZones, timestamp: timestamp)
    }
}

struct TemporalEventDetectorTests {

    /// Scenario 1 from the brief, reproduced almost verbatim: frames
    /// HAND, HAND, UNKNOWN, UNKNOWN, BATTLEFIELD, BATTLEFIELD should
    /// confirm exactly one `.objectMoved` HAND → BATTLEFIELD, not one per
    /// frame and not one for the transitional UNKNOWN frames.
    @Test("Card moved from Hand to Battlefield confirms once, after transitional frames")
    func handToBattlefieldConfirmsOnce() {
        var pipeline = Pipeline()
        var allEvents: [VisionEvent] = []
        allEvents += pipeline.step(handPoint)
        allEvents += pipeline.step(handPoint)
        allEvents += pipeline.step(unknownPoint)
        allEvents += pipeline.step(unknownPoint)
        allEvents += pipeline.step(battlefieldPoint)
        allEvents += pipeline.step(battlefieldPoint)

        let moves = allEvents.filter { $0.type == .objectMoved }
        #expect(moves.count == 1)
        #expect(moves.first?.previousZone == .player1Hand)
        #expect(moves.first?.currentZone == .battlefield)
        #expect(moves.first?.battlefieldSlot == 0)
    }

    @Test("Rune moved from Rune Deck to Rune Area is reported with objectType .rune")
    func runeDeckToRuneArea() {
        var pipeline = Pipeline()
        var allEvents: [VisionEvent] = []
        allEvents += pipeline.step(runeDeckPoint, type: .rune)
        allEvents += pipeline.step(runeDeckPoint, type: .rune)
        allEvents += pipeline.step(unknownPoint, type: .rune)
        allEvents += pipeline.step(unknownPoint, type: .rune)
        allEvents += pipeline.step(runeAreaPoint, type: .rune)
        allEvents += pipeline.step(runeAreaPoint, type: .rune)

        let moves = allEvents.filter { $0.type == .objectMoved }
        #expect(moves.count == 1)
        #expect(moves.first?.objectType == .rune)
        #expect(moves.first?.previousZone == .runeDeck)
        #expect(moves.first?.currentZone == .runeArea)
    }

    @Test("A 90° rotation confirms as objectRotated (Exhaust signature)")
    func rotationConfirmsAsExhaust() {
        var pipeline = Pipeline()
        var allEvents: [VisionEvent] = []
        allEvents += pipeline.step(battlefieldPoint, rotation: 0)
        allEvents += pipeline.step(battlefieldPoint, rotation: 0)
        allEvents += pipeline.step(battlefieldPoint, rotation: .pi / 2)
        allEvents += pipeline.step(battlefieldPoint, rotation: .pi / 2)

        let rotations = allEvents.filter { $0.type == .objectRotated }
        #expect(rotations.count == 1)
        #expect(rotations.first?.previousRotation == 0)
    }

    @Test("Rotating back to 0° after Exhaust confirms as a second objectRotated (Ready signature)")
    func rotationBackConfirmsAsReady() {
        var pipeline = Pipeline()
        // Establish Exhausted (90°).
        _ = pipeline.step(battlefieldPoint, rotation: 0)
        _ = pipeline.step(battlefieldPoint, rotation: .pi / 2)
        _ = pipeline.step(battlefieldPoint, rotation: .pi / 2)

        // Now Ready (back to 0°).
        var readyEvents: [VisionEvent] = []
        readyEvents += pipeline.step(battlefieldPoint, rotation: 0)
        readyEvents += pipeline.step(battlefieldPoint, rotation: 0)

        let rotations = readyEvents.filter { $0.type == .objectRotated }
        #expect(rotations.count == 1)
    }

    /// Scenario 6: picking a card up and returning it to the same zone
    /// must not emit a move — the net physical state didn't change.
    @Test("Picking up and returning a card to the same zone emits no objectMoved")
    func pickUpAndReturnEmitsNoMove() {
        var pipeline = Pipeline()
        var allEvents: [VisionEvent] = []
        allEvents += pipeline.step(handPoint)
        allEvents += pipeline.step(handPoint)
        allEvents += pipeline.step(unknownPoint)   // lifted
        allEvents += pipeline.step(handPoint)      // set back down
        allEvents += pipeline.step(handPoint)

        #expect(allEvents.filter { $0.type == .objectMoved }.isEmpty)
    }

    /// Scenario 7 at the event layer: a brief occlusion (no detections at
    /// all for a couple of frames, then visible again in the same zone)
    /// must not itself add any appear/disappear events beyond the single,
    /// legitimate `.objectAppeared` for the object's first-ever sighting.
    @Test("A brief occlusion produces no appear/disappear events beyond the initial appearance")
    func briefOcclusionProducesNoAppearDisappearEvents() {
        var pipeline = Pipeline()
        var allEvents: [VisionEvent] = []
        allEvents += pipeline.step(handPoint)                    // legitimate first sighting
        allEvents += pipeline.step(handPoint, present: false)    // occluded
        allEvents += pipeline.step(handPoint, present: false)    // still occluded
        allEvents += pipeline.step(handPoint)                    // visible again

        #expect(allEvents.filter { $0.type == .objectAppeared }.count == 1)
        #expect(allEvents.filter { $0.type == .objectDisappeared }.isEmpty)
    }
}
