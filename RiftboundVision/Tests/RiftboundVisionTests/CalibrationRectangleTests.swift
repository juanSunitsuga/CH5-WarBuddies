import Testing
import CoreGraphics
@testable import RiftboundVision

/// Corner handles used to set their corner's raw location, so the four
/// points could form any quadrilateral. One nudge left the mat crooked,
/// every zone inside it sheared with it, and the calibrated regions
/// stopped matching what the camera saw. These pin the invariant that
/// makes that impossible: the calibration quad is always an axis-aligned
/// rectangle, so a card's centroid lands in the zone it visually occupies.
@Suite("Calibration Rectangle Invariant")
struct CalibrationRectangleTests {

    private static func isAxisAlignedRectangle(_ c: PlaymatCalibration) -> Bool {
        c.topLeft.y == c.topRight.y
            && c.bottomLeft.y == c.bottomRight.y
            && c.topLeft.x == c.bottomLeft.x
            && c.topRight.x == c.bottomRight.x
    }

    @Test("A default calibration is a rectangle to begin with")
    func defaultIsRectangular() {
        let calibration = PlaymatCalibration.centered(in: CGSize(width: 1920, height: 1080), contentHeight: 1.4)
        #expect(Self.isAxisAlignedRectangle(calibration))
    }

    /// Zones are normalized against the quad, so a sheared quad shears
    /// every zone with it. With a rectangle, a normalized box maps to a
    /// box whose edges stay parallel to the frame.
    @Test("Zones stay axis-aligned when the calibration is a rectangle")
    func zonesStayAxisAlignedUnderARectangle() {
        let calibration = PlaymatCalibration.centered(in: CGSize(width: 1920, height: 1080), contentHeight: 1.4)

        for zone in calibration.boardZones() {
            let polygon = zone.polygon
            #expect(polygon.count == 4)
            // Corners in template order: TL, TR, BR, BL.
            #expect(abs(polygon[0].y - polygon[1].y) < 0.001, "\(zone.type) top edge isn't level")
            #expect(abs(polygon[3].y - polygon[2].y) < 0.001, "\(zone.type) bottom edge isn't level")
            #expect(abs(polygon[0].x - polygon[3].x) < 0.001, "\(zone.type) left edge isn't vertical")
            #expect(abs(polygon[1].x - polygon[2].x) < 0.001, "\(zone.type) right edge isn't vertical")
        }
    }

    /// The failure this replaces: a quad dragged out of square puts a
    /// point in a different zone than the one it visually sits in.
    @Test("A sheared quad misplaces a point that a rectangle resolves correctly")
    func shearedQuadMisplacesPoints() {
        let rectangular = PlaymatCalibration(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 1000, y: 0),
            bottomRight: CGPoint(x: 1000, y: 800),
            bottomLeft: CGPoint(x: 0, y: 800)
        )
        // Same corners, except the top-right is dragged well down —
        // exactly the shape a free-corner drag produces.
        let sheared = PlaymatCalibration(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 1000, y: 300),
            bottomRight: CGPoint(x: 1000, y: 800),
            bottomLeft: CGPoint(x: 0, y: 800)
        )

        // The mat's own centre in normalized space.
        let center = CGPoint(x: 0.5, y: 0.5)
        let straight = rectangular.map(center)
        let crooked = sheared.map(center)

        #expect(straight.y == 400)
        #expect(crooked.y != straight.y, "A sheared quad moves the mat's centre — and every zone with it.")
    }
}
