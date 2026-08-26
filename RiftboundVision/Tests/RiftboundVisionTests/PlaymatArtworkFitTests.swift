import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import RiftboundVision

/// The border artwork is drawn by stretching each SVG into its zone's
/// rect, so a zone whose proportions differ from its artwork's visibly
/// smears the frame's corner strokes. These tests assert the template's
/// geometry is derived from the assets' real pixel dimensions — the thing
/// that makes that stretch a no-op — so re-exporting the art at a new size
/// without re-deriving the template fails here instead of on screen.
struct PlaymatArtworkFitTests {

    /// Mirrors `PlaymatOverlayView.frame(for:)`'s zone → asset mapping.
    /// Exhaustive for the same reason that one is: a new zone should
    /// break this test rather than quietly borrow another zone's art.
    private static func assetName(for zone: Zone) -> String {
        switch zone {
        case .battlefield, .base: return "Rectangle 1"
        case .player1Hand, .player2Hand: return "Rectangle 2"
        case .runeArea: return "Rectangle 3"
        case .mainDeck: return "Rectangle 4"
        case .runeDeck: return "Rectangle 5"
        case .trash: return "Rectangle 6"
        case .legend, .champion: return "Rectangle 7"
        case .unknown: return "Rectangle 1"
        }
    }

    private static func assetSize(_ name: String) throws -> CGSize {
        let url = try #require(RiftboundVisionResources.bundle.url(forResource: name, withExtension: "svg"))
        let image = try #require(NSImage(contentsOf: url))
        // `image.size`, not a representation's `pixelsWide`: these are
        // vector assets, and an SVG rep reports no pixel dimensions.
        return image.size
    }

    private static func normalizedSize(_ polygon: [CGPoint]) -> CGSize {
        let xs = polygon.map(\.x), ys = polygon.map(\.y)
        return CGSize(
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    @Test("Every zone's aspect ratio matches its border artwork's, so nothing stretches when drawn")
    func zoneAspectRatiosMatchTheirArtwork() throws {
        // The mat (the 0...1 unit square) isn't square, so a normalized
        // size has to be scaled back into mat-pixel space before its
        // proportions mean anything.
        let matAspect = RiftboundPlaymatTemplate.matAspectRatio

        for template in RiftboundPlaymatTemplate.singlePlayerZones() {
            let art = try Self.assetSize(Self.assetName(for: template.zone))
            let normalized = Self.normalizedSize(template.normalizedPolygon)

            let artAspect = art.width / art.height
            let zoneAspect = (normalized.width * matAspect) / normalized.height

            #expect(
                abs(artAspect - zoneAspect) < 0.001,
                "\(template.zone) is \(zoneAspect) wide-to-tall but its artwork is \(artAspect) — it will stretch."
            )
        }
    }

    /// The 3pt gutter isn't a tuning knob: it's the only value that makes
    /// all three rows of artwork total the same width, which is what lets
    /// the grid tile without gaps or overlap.
    @Test("All three mat rows span the full width, leaving no gap or overlap")
    func rowsSpanTheFullMatWidth() {
        let zones = RiftboundPlaymatTemplate.singlePlayerZones()
        // Rune Area is deliberately absent: its artwork is 434 against
        // the mat's 433, so it overhangs half a point at each edge rather
        // than being squeezed to fit. Every *other* row tiles exactly.
        let rows: [[Zone]] = [
            [.battlefield, .legend, .champion],
            [.runeDeck, .base, .mainDeck],
            [.player1Hand, .trash]
        ]

        for row in rows {
            let boxes = row.compactMap { zone in
                zones.first { $0.zone == zone }?.normalizedPolygon
            }
            #expect(boxes.count == row.count)

            let minX = boxes.compactMap { $0.map(\.x).min() }.min() ?? 0
            let maxX = boxes.compactMap { $0.map(\.x).max() }.max() ?? 0
            #expect(abs(minX - 0) < 0.0001, "Row \(row) doesn't start at the mat's left edge.")
            #expect(abs(maxX - 1) < 0.0001, "Row \(row) doesn't reach the mat's right edge.")
        }
    }

    /// A default calibration must be built at the mat's own proportion,
    /// otherwise every frame is pre-stretched before the user has dragged
    /// a single corner.
    @Test("The default calibration quad is built at the mat's real aspect ratio")
    func defaultCalibrationPreservesMatAspectRatio() {
        let calibration = PlaymatCalibration.centered(
            in: CGSize(width: 1920, height: 1080),
            contentHeight: 1.4
        )
        let width = calibration.topRight.x - calibration.topLeft.x
        let height = calibration.bottomLeft.y - calibration.topLeft.y

        #expect(abs((width / height) - RiftboundPlaymatTemplate.matAspectRatio) < 0.001)
    }
}
