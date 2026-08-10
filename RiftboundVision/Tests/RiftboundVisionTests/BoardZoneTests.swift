import Testing
import CoreGraphics
@testable import RiftboundVision

struct BoardZoneTests {
    @Test("A point inside a calibrated rectangle resolves to that zone")
    func pointInsideResolves() {
        let hand = BoardZone(type: .player1Hand, polygon: [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
        ])
        let mapper = ZoneMapper(zones: [hand])

        #expect(mapper.zone(for: CGPoint(x: 50, y: 50)) == .player1Hand)
    }

    @Test("A point outside every calibrated zone resolves to unknown")
    func pointOutsideResolvesUnknown() {
        let hand = BoardZone(type: .player1Hand, polygon: [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
        ])
        let mapper = ZoneMapper(zones: [hand])

        #expect(mapper.zone(for: CGPoint(x: 500, y: 500)) == .unknown)
    }

    @Test("Two Battlefield instances are disambiguated by battlefieldSlot")
    func multipleBattlefieldsDisambiguated() {
        let battlefieldA = BoardZone(
            type: .battlefield,
            polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)],
            battlefieldSlot: 0
        )
        let battlefieldB = BoardZone(
            type: .battlefield,
            polygon: [CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 100), CGPoint(x: 200, y: 100)],
            battlefieldSlot: 1
        )
        let mapper = ZoneMapper(zones: [battlefieldA, battlefieldB])

        #expect(mapper.boardZone(for: CGPoint(x: 50, y: 50))?.battlefieldSlot == 0)
        #expect(mapper.boardZone(for: CGPoint(x: 250, y: 50))?.battlefieldSlot == 1)
    }
}
