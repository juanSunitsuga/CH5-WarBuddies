import Testing
import CoreGraphics
@testable import RiftboundVision

struct PlaymatCalibrationTests {

    private let calibration = PlaymatCalibration(
        topLeft: CGPoint(x: 100, y: 50),
        topRight: CGPoint(x: 500, y: 60),
        bottomRight: CGPoint(x: 480, y: 400),
        bottomLeft: CGPoint(x: 90, y: 390)
    )

    @Test("The 4 template corners map exactly onto the calibration's 4 corners")
    func cornersMapExactly() {
        #expect(calibration.map(CGPoint(x: 0, y: 0)) == calibration.topLeft)
        #expect(calibration.map(CGPoint(x: 1, y: 0)) == calibration.topRight)
        #expect(calibration.map(CGPoint(x: 1, y: 1)) == calibration.bottomRight)
        #expect(calibration.map(CGPoint(x: 0, y: 1)) == calibration.bottomLeft)
    }

    @Test("The template center maps to the average of the 4 corners")
    func centerMapsToAverage() {
        let center = calibration.map(CGPoint(x: 0.5, y: 0.5))
        let expectedX = (calibration.topLeft.x + calibration.topRight.x + calibration.bottomRight.x + calibration.bottomLeft.x) / 4
        let expectedY = (calibration.topLeft.y + calibration.topRight.y + calibration.bottomRight.y + calibration.bottomLeft.y) / 4

        #expect(abs(center.x - expectedX) < 0.001)
        #expect(abs(center.y - expectedY) < 0.001)
    }

    @Test("boardZones() defaults to the single-player template, one BoardZone per zone, all within the calibration's bounding rect")
    func boardZonesStayWithinCalibratedBounds() {
        let zones = calibration.boardZones()

        #expect(zones.count == RiftboundPlaymatTemplate.singlePlayerZones().count)

        let bounds = calibration.boundingRect
        for zone in zones where zone.type != .player1Hand && zone.type != .player2Hand {
            for point in zone.polygon {
                // Bilinear interpolation of points inside the unit square
                // always stays inside the bounding rect of the 4 corners.
                // Hand is excluded on purpose — it deliberately extends
                // past y=1 (see its doc comment in
                // `RiftboundPlaymatTemplate`), so its points fall outside
                // this same-quad bound until the user's own calibration
                // corners are dragged past the mat to include it.
                #expect(bounds.insetBy(dx: -1, dy: -1).contains(point))
            }
        }
    }

    @Test("Single-player template has exactly one Legend and one Champion zone, owned by the given player")
    func singlePlayerLegendAndChampionZonesExist() {
        let zones = calibration.boardZones(template: RiftboundPlaymatTemplate.singlePlayerZones(owner: .player2))

        let legends = zones.filter { $0.type == .legend }
        let champions = zones.filter { $0.type == .champion }

        #expect(legends.count == 1)
        #expect(legends.first?.owner == .player2)
        #expect(champions.count == 1)
        #expect(champions.first?.owner == .player2)
    }

    @Test("Two-player template has Legend and Champion zones for both players")
    func twoPlayerLegendAndChampionZonesExistForBothPlayers() {
        let zones = calibration.boardZones(template: RiftboundPlaymatTemplate.twoPlayerZones)

        #expect(zones.contains { $0.type == .legend && $0.owner == .player1 })
        #expect(zones.contains { $0.type == .legend && $0.owner == .player2 })
        #expect(zones.contains { $0.type == .champion && $0.owner == .player1 })
        #expect(zones.contains { $0.type == .champion && $0.owner == .player2 })
    }

    @Test("The single-player template has exactly one, unowned Battlefield zone at slot 0")
    func singlePlayerBattlefieldZoneIsUnownedAtSlotZero() {
        let zones = calibration.boardZones()
        let battlefields = zones.filter { $0.type == .battlefield }

        #expect(battlefields.count == 1)
        #expect(battlefields.allSatisfy { $0.owner == nil })
        #expect(battlefields.first?.battlefieldSlot == 0)
    }

    @Test("Single-player template has exactly one Hand zone, owned by and named for the given player")
    func singlePlayerHandZoneExists() {
        let zones = calibration.boardZones(template: RiftboundPlaymatTemplate.singlePlayerZones(owner: .player2))

        let hands = zones.filter { $0.type == .player1Hand || $0.type == .player2Hand }
        #expect(hands.count == 1)
        #expect(hands.first?.type == .player2Hand)
        #expect(hands.first?.owner == .player2)
    }

    @Test("A point resolved via ZoneMapper against calibrated zones lands in the expected Battlefield slot")
    func zoneMapperResolvesCalibratedZonesCorrectly() {
        let mapper = ZoneMapper(zones: calibration.boardZones())

        // Single-player template's first Battlefield slot spans normalized
        // x 0.055...0.33, y 0.065...0.345 — its center should resolve as
        // Battlefield #0 regardless of calibration skew.
        let center = calibration.map(CGPoint(x: 0.1925, y: 0.205))
        let boardZone = mapper.boardZone(for: center)

        #expect(boardZone?.type == .battlefield)
        #expect(boardZone?.battlefieldSlot == 0)
    }
}
