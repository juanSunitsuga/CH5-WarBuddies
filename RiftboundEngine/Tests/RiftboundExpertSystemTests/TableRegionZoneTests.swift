import Testing
@testable import RiftboundExpertSystem

/// `TableRegion.location` is `nil` for every zone that isn't a Base or a
/// Battlefield (rule 106), so anything rendering a region by switching on
/// `location` collapses six real places into one "unknown". These pin the
/// distinction so a display or a rule can't quietly rely on the wrong one.
@Suite("Table Region Zones")
struct TableRegionZoneTests {
    private let owner = PlayerID()
    private let battlefieldID = BattlefieldID()

    /// Rule 106: Base and Battlefield are Locations; nothing else is.
    @Test("Only Base and Battlefield resolve to a Location")
    func onlyBoardZonesAreLocations() {
        #expect(TableRegion(owner: owner, zone: .base).location == .base(owner))
        #expect(TableRegion(owner: owner, zone: .battlefield(battlefieldID)).location == .battlefield(battlefieldID))

        for zone in [TableZone.hand, .mainDeck, .runeDeck, .runeArea, .trash, .banishment, .legendZone, .championZone] {
            #expect(TableRegion(owner: owner, zone: zone).location == nil, "\(zone) is a Zone, not a Location.")
        }
    }

    /// Every zone stays distinguishable, which is the whole point of the
    /// widening — `location` alone can't tell the Trash from the Hand.
    @Test("Every zone is distinguishable from every other")
    func zonesAreDistinct() {
        let all: [TableZone] = [
            .hand, .base, .battlefield(battlefieldID), .mainDeck,
            .runeDeck, .runeArea, .trash, .banishment, .legendZone, .championZone
        ]
        for (index, zone) in all.enumerated() {
            for other in all[(index + 1)...] {
                #expect(zone != other, "\(zone) and \(other) must not compare equal.")
            }
        }
    }

    @Test("Only the hand reports itself as the hand")
    func handIsTheOnlyHandRegion() {
        #expect(TableRegion(owner: owner, zone: .hand).isHandRegion)
        for zone in [TableZone.base, .battlefield(battlefieldID), .mainDeck, .trash, .runeArea] {
            #expect(!TableRegion(owner: owner, zone: zone).isHandRegion)
        }
    }

    /// The Location-shaped initializer predates `TableZone`; call sites
    /// still using it must land on the same zones.
    @Test("The legacy Location initializer maps onto the same zones")
    func legacyInitializerAgrees() {
        #expect(TableRegion(owner: owner, location: .base(owner), isHandRegion: false).zone == .base)
        #expect(TableRegion(owner: owner, location: .battlefield(battlefieldID), isHandRegion: false).zone == .battlefield(battlefieldID))
        #expect(TableRegion(owner: owner, location: nil, isHandRegion: true).zone == .hand)
    }
}
