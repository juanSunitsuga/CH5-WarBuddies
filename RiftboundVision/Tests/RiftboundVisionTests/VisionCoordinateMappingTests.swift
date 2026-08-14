import Testing
import CoreGraphics
@testable import RiftboundVision

/// Vision reports observations normalized to the request's
/// `regionOfInterest`, not to the whole image. Multiplying such a box by
/// the full image size — which is what happened when region-of-interest
/// scanning was introduced — squashes every detection toward the origin,
/// so the boxes and tracked centroids drift off the cards they belong to.
///
/// The model can't be loaded in tests, so the arithmetic lives in a free
/// function and is pinned here instead.
@Suite("Vision Coordinate Mapping")
struct VisionCoordinateMappingTests {
    private static let imageSize = CGSize(width: 1920, height: 1080)
    private static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test("With no region of interest, a centred box maps to the centre of the image")
    func fullFrameMapsToWholeImage() {
        let rect = imageRect(
            fromNormalized: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            visionRegionOfInterest: Self.fullFrame,
            imageSize: Self.imageSize
        )
        #expect(rect.midX == 960)
        #expect(rect.midY == 540)
        #expect(rect.width == 960)
        #expect(rect.height == 540)
    }

    /// Vision's origin is bottom-left, `Detection`'s is top-left, so the
    /// vertical axis has to flip.
    @Test("The vertical axis flips from Vision's bottom-left origin")
    func verticalAxisFlips() {
        // Bottom strip in Vision space → top strip in image space.
        let rect = imageRect(
            fromNormalized: CGRect(x: 0, y: 0, width: 1, height: 0.1),
            visionRegionOfInterest: Self.fullFrame,
            imageSize: Self.imageSize
        )
        #expect(rect.minY == 972)   // 1080 - 108
    }

    /// The regression: a box reported inside a region has to be lifted back
    /// into whole-image space before being scaled.
    @Test("A box inside a region of interest maps back to its true image position")
    func regionRelativeBoxMapsBack() {
        // Region covering the right half, vertically centred.
        let region = CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.5)
        // Dead centre *of that region*.
        let rect = imageRect(
            fromNormalized: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            visionRegionOfInterest: region,
            imageSize: Self.imageSize
        )

        // Region centre in Vision space is (0.75, 0.5) → image (1440, 540).
        #expect(abs(rect.midX - 1440) < 0.001)
        #expect(abs(rect.midY - 540) < 0.001)
        // And it's scaled by the region, not the frame: 0.2 × 0.5 × 1920.
        #expect(abs(rect.width - 192) < 0.001)
    }

    /// What the bug actually looked like: treating a region-relative box as
    /// whole-image collapses it toward the origin. Pinned so the two are
    /// never conflated again.
    @Test("Ignoring the region misplaces the box — the failure this guards against")
    func ignoringTheRegionMisplacesTheBox() {
        let region = CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.5)
        let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

        let correct = imageRect(fromNormalized: box, visionRegionOfInterest: region, imageSize: Self.imageSize)
        let naive = imageRect(fromNormalized: box, visionRegionOfInterest: Self.fullFrame, imageSize: Self.imageSize)

        #expect(correct.midX != naive.midX)
        #expect(abs(correct.midX - naive.midX) > 400, "The old maths was off by hundreds of pixels.")
    }

    /// Round-trip: a pixel rect converted into Vision's convention and used
    /// as a region must map that region's own full extent back to itself.
    @Test("visionRegion round-trips with imageRect")
    func regionRoundTrips() {
        let matRect = CGRect(x: 300, y: 200, width: 1200, height: 700)
        let region = visionRegion(from: matRect, imageSize: Self.imageSize)

        // The whole region, expressed as a region-relative unit box.
        let rect = imageRect(fromNormalized: Self.fullFrame, visionRegionOfInterest: region, imageSize: Self.imageSize)

        #expect(abs(rect.minX - matRect.minX) < 0.001)
        #expect(abs(rect.minY - matRect.minY) < 0.001)
        #expect(abs(rect.width - matRect.width) < 0.001)
        #expect(abs(rect.height - matRect.height) < 0.001)
    }
}
