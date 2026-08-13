import Testing
import CoreGraphics
import RiftboundExpertSystem
@testable import RiftboundVision

/// A Battlefield is deliberately unowned (rule 181 — Control is contested,
/// not a property of the printed region), so both `BoardZone.owner` and
/// `Zone.impliedOwner` are `nil` there. `TableRegion` still requires a
/// `PlayerID`, so an event whose track *began* on a Battlefield carried no
/// seat and was dropped outright.
///
/// That's precisely a card being played: picking it up ends one track, and
/// setting it down on the Battlefield starts a new one whose first sighting
/// is an unowned zone. The result was a log full of Hand events and nothing
/// else — the played card never registered at all.
@Suite("Battlefield Seat Attribution")
struct BattlefieldSeatTests {
    private static let playerID = PlayerID()
    private static let battlefieldID = BattlefieldID()
    private static let battlefieldCenter = CGPoint(x: 300, y: 200)

    private static func zoneMapper() -> ZoneMapper {
        ZoneMapper(zones: [
            BoardZone(
                type: .player1Hand,
                polygon: [CGPoint(x: 0, y: 700), CGPoint(x: 800, y: 700), CGPoint(x: 800, y: 1100), CGPoint(x: 0, y: 1100)],
                owner: .player1
            ),
            // Unowned, exactly as `RiftboundPlaymatTemplate` builds it.
            BoardZone(
                type: .battlefield,
                polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 0), CGPoint(x: 800, y: 400), CGPoint(x: 0, y: 400)],
                owner: nil,
                battlefieldSlot: 0
            )
        ])
    }

    private static func makeAdapter(defaultSeat: Player?) -> ExpertSystemAdapter {
        ExpertSystemAdapter(
            zoneMapper: zoneMapper(),
            playerCalibration: [.player1: playerID],
            battlefieldCalibration: [0: battlefieldID],
            defaultSeat: defaultSeat
        )
    }

    private static func detection(label: String) -> Detection {
        Detection(
            type: .card,
            center: battlefieldCenter,
            boundingBox: CGRect(x: 260, y: 145, width: 80, height: 110),
            rotation: 0,
            confidence: 0.95,
            recognizedLabel: label
        )
    }

    /// Drives enough polls for `TemporalEventDetector`'s confirmation to
    /// fire, then reports what actually reached the Expert System.
    private static func collectEvents(from adapter: ExpertSystemAdapter) async -> [ObservedTableEvent] {
        let stream = adapter.events()
        for frame in 1...4 {
            adapter.ingest(
                detections: [detection(label: "Sneaky Deckhand")],
                frameIndex: frame,
                timestamp: Double(frame) * 0.35
            )
        }
        adapter.finish()

        var collected: [ObservedTableEvent] = []
        for await event in stream { collected.append(event) }
        return collected
    }

    @Test("A card appearing on the unowned Battlefield is attributed to the default seat")
    func battlefieldAppearanceIsForwarded() async {
        let adapter = Self.makeAdapter(defaultSeat: .player1)
        let events = await Self.collectEvents(from: adapter)

        #expect(!events.isEmpty, "A card placed on the Battlefield must reach the Expert System.")
        guard case .cardAppeared(let region) = events.first?.kind else {
            Issue.record("Expected a .cardAppeared on the Battlefield, got \(String(describing: events.first?.kind))")
            return
        }
        #expect(region.owner == Self.playerID)
        #expect(region.location == .battlefield(Self.battlefieldID))
        #expect(adapter.unrepresentableZoneEvents.isEmpty)
    }

    /// Pins the old behaviour as the regression it was: with no seat to
    /// fall back on there is genuinely no `TableRegion` to build, so the
    /// event is recorded as unrepresentable rather than silently vanishing.
    @Test("Without a default seat the same event is dropped as unrepresentable")
    func withoutDefaultSeatEventIsDropped() async {
        let adapter = Self.makeAdapter(defaultSeat: nil)
        let events = await Self.collectEvents(from: adapter)

        #expect(events.isEmpty)
        #expect(!adapter.unrepresentableZoneEvents.isEmpty, "A dropped event must still be recorded as unrepresentable.")
    }
}
