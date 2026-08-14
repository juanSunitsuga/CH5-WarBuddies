import Testing
import CoreGraphics
import RiftboundExpertSystem
@testable import RiftboundVision

/// Six of the mat's regions — Main Deck, Rune Deck, Rune Area, Trash,
/// Legend and Champion — had no `TableRegion` representation, so a card
/// entering any of them was dropped at the boundary into
/// `unrepresentableZoneEvents`. Draw and Channel Rune were therefore
/// unreachable however well tracking worked, and the Tracking Log's "not
/// sent to the rules engine" note was the visible symptom.
@Suite("Zone Coverage")
struct ZoneCoverageTests {
    private static let playerID = PlayerID()
    private static let battlefieldID = BattlefieldID()

    /// One 200×200 cell per zone, laid out left to right.
    private static let zones: [(Zone, CGPoint)] = [
        (.player1Hand, CGPoint(x: 100, y: 100)),
        (.base, CGPoint(x: 300, y: 100)),
        (.battlefield, CGPoint(x: 500, y: 100)),
        (.mainDeck, CGPoint(x: 700, y: 100)),
        (.runeDeck, CGPoint(x: 900, y: 100)),
        (.runeArea, CGPoint(x: 1100, y: 100)),
        (.legend, CGPoint(x: 1300, y: 100)),
        (.champion, CGPoint(x: 1500, y: 100))
    ]

    private static func zoneMapper() -> ZoneMapper {
        ZoneMapper(zones: zones.enumerated().map { index, entry in
            let x = CGFloat(index) * 200
            return BoardZone(
                type: entry.0,
                polygon: [
                    CGPoint(x: x, y: 0), CGPoint(x: x + 200, y: 0),
                    CGPoint(x: x + 200, y: 200), CGPoint(x: x, y: 200)
                ],
                owner: .player1,
                battlefieldSlot: entry.0 == .battlefield ? 0 : nil
            )
        })
    }

    private static func makeAdapter() -> ExpertSystemAdapter {
        ExpertSystemAdapter(
            zoneMapper: zoneMapper(),
            playerCalibration: [.player1: playerID],
            battlefieldCalibration: [0: battlefieldID],
            // Trash is a discard zone by default, which would suppress the
            // very event this suite is checking reaches the boundary.
            tracker: ObjectTracker(discardZones: []),
            defaultSeat: .player1
        )
    }

    private static func detection(at center: CGPoint, label: String) -> Detection {
        Detection(
            type: .card,
            center: center,
            boundingBox: CGRect(x: center.x - 35, y: center.y - 50, width: 70, height: 100),
            rotation: 0,
            confidence: 0.95,
            recognizedLabel: label
        )
    }

    /// Every calibrated zone must produce a forwardable event — nothing
    /// left in `unrepresentableZoneEvents`.
    @Test("A card in any calibrated zone reaches the Expert System")
    func everyZoneIsForwardable() async {
        let adapter = Self.makeAdapter()
        let stream = adapter.events()

        // One card per zone, held long enough to confirm.
        for frame in 1...4 {
            adapter.ingest(
                detections: Self.zones.enumerated().map { index, entry in
                    Self.detection(at: entry.1, label: "Card\(index)")
                },
                frameIndex: frame,
                timestamp: Double(frame) * 0.2
            )
        }
        adapter.finish()

        var events: [ObservedTableEvent] = []
        for await event in stream { events.append(event) }

        #expect(events.count == Self.zones.count, "Every zone should forward exactly one appearance.")
        #expect(adapter.unrepresentableZoneEvents.isEmpty, "No zone should be dropped for lack of a representation.")
    }

    /// The specific zones that used to be dropped, named individually so a
    /// regression says which one broke.
    @Test("Main Deck, Rune Deck, Rune Area, Trash, Legend and Champion all map")
    func previouslyDroppedZonesMap() {
        let owner = Self.playerID
        let cases: [(TableZone, String)] = [
            (.mainDeck, "Main Deck"), (.runeDeck, "Rune Deck"), (.runeArea, "Rune Area"),
            (.trash, "Trash"), (.legendZone, "Legend"), (.championZone, "Champion")
        ]
        for (zone, name) in cases {
            let region = TableRegion(owner: owner, zone: zone)
            #expect(region.zone == zone, "\(name) lost its zone.")
            // Rule 106: none of these are Locations, and that stays true.
            #expect(region.location == nil, "\(name) is a Zone, not a Location.")
            #expect(!region.isHandRegion)
        }
    }

    /// Rule 106 must survive the widening: Base and Battlefield are still
    /// the only Locations, and Hand is still the hand.
    @Test("Locations and the hand still read correctly")
    func locationsSurviveTheWidening() {
        let owner = Self.playerID
        #expect(TableRegion(owner: owner, zone: .base).location == .base(owner))
        #expect(TableRegion(owner: owner, zone: .battlefield(Self.battlefieldID)).location == .battlefield(Self.battlefieldID))
        #expect(TableRegion(owner: owner, zone: .hand).isHandRegion)
        #expect(TableRegion(owner: owner, zone: .hand).location == nil)
    }
}
