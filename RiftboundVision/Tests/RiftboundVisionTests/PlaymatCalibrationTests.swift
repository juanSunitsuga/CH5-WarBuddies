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

    @Test("boardZones() produces one BoardZone per template zone, all within the calibration's bounding rect")
    func boardZonesStayWithinCalibratedBounds() {
        let zones = calibration.boardZones()

        #expect(zones.count == RiftboundPlaymatTemplate.zones.count)

        let bounds = calibration.boundingRect
        for zone in zones {
            for point in zone.polygon {
                // Bilinear interpolation of points inside the unit square
                // always stays inside the bounding rect of the 4 corners.
                #expect(bounds.insetBy(dx: -1, dy: -1).contains(point))
            }
        }
    }

    @Test("Both Legend and Champion zones exist for both players")
    func legendAndChampionZonesExistForBothPlayers() {
        let zones = calibration.boardZones()

        #expect(zones.contains { $0.type == .legend && $0.owner == .player1 })
        #expect(zones.contains { $0.type == .legend && $0.owner == .player2 })
        #expect(zones.contains { $0.type == .champion && $0.owner == .player1 })
        #expect(zones.contains { $0.type == .champion && $0.owner == .player2 })
    }

    @Test("The shared Battlefield zone has no owner and carries the given battlefieldSlot")
    func battlefieldZoneIsUnownedWithSlot() {
        let zones = calibration.boardZones(battlefieldSlot: 3)
        let battlefield = zones.first { $0.type == .battlefield }

        #expect(battlefield?.owner == nil)
        #expect(battlefield?.battlefieldSlot == 3)
    }

    @Test("A point resolved via ZoneMapper against calibrated zones lands in the expected zone")
    func zoneMapperResolvesCalibratedZonesCorrectly() {
        let mapper = ZoneMapper(zones: calibration.boardZones())

        // Template battlefield spans normalized y 0.32...0.68 — dead
        // center of the mat should resolve as Battlefield regardless of
        // calibration skew.
        let center = calibration.map(CGPoint(x: 0.5, y: 0.5))
        #expect(mapper.zone(for: center) == .battlefield)
    }
}
