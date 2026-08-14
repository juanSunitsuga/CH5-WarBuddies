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

    /// `identify(objectID:as:)` requires knowing a `TrackedObjectID` in
    /// advance, but `tracker`/`temporalDetector` are private to this
    /// adapter — nothing outside it can ever discover the right ID to call
    /// that with. `Detection.recognizedLabel` (from a real recognizer like
    /// `CoreMLCardDetector`) is what actually makes automatic
    /// identification possible, carried through `TrackedObject` →
    /// `VisionEvent.recognizedLabel` → here.
    @Test("A detection with a recognizedLabel is auto-identified without calling identify(objectID:as:)")
    func recognizedLabelAutoIdentifiesWithoutManualCall() async {
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
            tracker: ObjectTracker(matchDistanceThreshold: 2000)
        )

        let stream = adapter.events()

        func card(at point: CGPoint, label: String) -> Detection {
            Detection(type: .card, center: point, boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30), rotation: 0, confidence: 0.95, recognizedLabel: label)
        }

        adapter.ingest(detections: [card(at: CGPoint(x: 25, y: 25), label: "Garen - Rugged")], frameIndex: 0, timestamp: 0)
        adapter.ingest(detections: [card(at: CGPoint(x: 25, y: 25), label: "Garen - Rugged")], frameIndex: 1, timestamp: 1.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 1000, y: 1000), label: "Garen - Rugged")], frameIndex: 2, timestamp: 2.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 1000, y: 1000), label: "Garen - Rugged")], frameIndex: 3, timestamp: 3.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 225, y: 225), label: "Garen - Rugged")], frameIndex: 4, timestamp: 4.0 / 30)
        adapter.ingest(detections: [card(at: CGPoint(x: 225, y: 225), label: "Garen - Rugged")], frameIndex: 5, timestamp: 5.0 / 30)
        adapter.finish()

        var received: [ObservedTableEvent] = []
        for await event in stream { received.append(event) }

        let moved = received.first { if case .cardMoved = $0.kind { return true }; return false }
        #expect(moved?.card?.cardDefinitionID == CardDefID(rawValue: "Garen - Rugged"))
    }

    /// `runeCounts(for:)` resolves each Rune's identity the same way
    /// `card(at:)` does (`recognizedLabel` → `resolveLabel`), then a second
    /// hop (`resolveDomain`) to bucket by Domain — verifies both hops, that
    /// non-Rune objects and the other player's Rune Area are excluded, and
    /// that an object whose Domain can't be resolved is dropped rather than
    /// mis-bucketed.
    @Test("runeCounts(for:) buckets live Rune Area occupants by Domain")
    func runeCountsBucketsByDomain() {
        let playerA = PlayerID()
        let zoneMapper = ZoneMapper(zones: [
            BoardZone(type: .runeArea, polygon: square(0, 0), owner: .player1),
            BoardZone(type: .runeArea, polygon: square(400, 0), owner: .player2)
        ])
        let adapter = ExpertSystemAdapter(
            zoneMapper: zoneMapper,
            playerCalibration: [.player1: playerA],
            tracker: ObjectTracker(matchDistanceThreshold: 2000),
            resolveLabel: { CardDefID(rawValue: $0) },
            resolveDomain: { definitionID in
                switch definitionID.rawValue {
                case "Fury Rune": return .fury
                case "Chaos Rune": return .chaos
                case "Mystery Rune": return nil  // known label, deliberately unresolvable Domain
                default: return nil
                }
            }
        )

        func rune(at point: CGPoint, label: String) -> Detection {
            Detection(type: .rune, center: point, boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30), rotation: 0, confidence: 0.95, recognizedLabel: label)
        }
        func card(at point: CGPoint) -> Detection {
            Detection(type: .card, center: point, boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30), rotation: 0, confidence: 0.95)
        }

        adapter.ingest(detections: [
            rune(at: CGPoint(x: 25, y: 25), label: "Fury Rune"),
            rune(at: CGPoint(x: 26, y: 26), label: "Fury Rune"),
            rune(at: CGPoint(x: 27, y: 27), label: "Chaos Rune"),
            rune(at: CGPoint(x: 28, y: 28), label: "Mystery Rune"),
            card(at: CGPoint(x: 29, y: 29)),                          // not a Rune — excluded
            rune(at: CGPoint(x: 425, y: 25), label: "Fury Rune")       // player2's Rune Area — excluded
        ], frameIndex: 0, timestamp: 0)

        let counts = adapter.runeCounts(for: playerA)

        #expect(counts[.fury] == 2)
        #expect(counts[.chaos] == 1)
        #expect(counts[.mind] == nil)
        #expect(counts.values.reduce(0, +) == 3)   // the Mystery Rune and the plain card are both dropped
    }

    /// `exhaustedRuneCount(for:)` is Domain-agnostic (Energy is paid by
    /// exhausting Runes regardless of Domain, 130.2) but shares the same
    /// zone/owner filtering `runeCounts(for:)` does — a wide (landscape)
    /// bounding box reads as `.exhausted` per `CardStance`, a tall one as
    /// `.ready`, and non-Rune objects / the other player's Rune Area are
    /// excluded the same way.
    @Test("exhaustedRuneCount(for:) counts only Exhausted Runes in this player's Rune Area")
    func exhaustedRuneCountCountsOnlyExhaustedInOwnArea() {
        let playerA = PlayerID()
        let zoneMapper = ZoneMapper(zones: [
            BoardZone(type: .runeArea, polygon: square(0, 0), owner: .player1),
            BoardZone(type: .runeArea, polygon: square(400, 0), owner: .player2)
        ])
        let adapter = ExpertSystemAdapter(
            zoneMapper: zoneMapper,
            playerCalibration: [.player1: playerA],
            tracker: ObjectTracker(matchDistanceThreshold: 2000)
        )

        func rune(at point: CGPoint, exhausted: Bool) -> Detection {
            // Ready = taller than wide (portrait); Exhausted = wider than
            // tall (landscape) — see CardStance.
            let box = exhausted
                ? CGRect(x: point.x - 15, y: point.y - 10, width: 30, height: 20)
                : CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30)
            return Detection(type: .rune, center: point, boundingBox: box, rotation: 0, confidence: 0.95)
        }

        adapter.ingest(detections: [
            rune(at: CGPoint(x: 25, y: 25), exhausted: true),
            rune(at: CGPoint(x: 26, y: 26), exhausted: true),
            rune(at: CGPoint(x: 27, y: 27), exhausted: false),
            rune(at: CGPoint(x: 425, y: 25), exhausted: true)   // player2's Rune Area — excluded
        ], frameIndex: 0, timestamp: 0)

        #expect(adapter.exhaustedRuneCount(for: playerA) == 2)
    }
}
