import CoreGraphics

/// The one-time (per camera setup) alignment of `RiftboundPlaymatTemplate`'s
/// normalized zone geometry onto wherever the physical mat actually sits
/// in the camera frame — 4 corners the user drags into place, same
/// philosophy as `BoardZone` generally: "calibrated polygons/rectangles
/// rather than repeatedly detected by ML." No mat-edge computer vision
/// here on purpose; a printed mat's edges are hard to segment reliably
/// under arbitrary lighting/angle, and this is a one-time setup cost, not
/// a per-frame one.
public struct PlaymatCalibration: Sendable, Equatable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// A reasonable starting quad before the user has dragged anything —
    /// horizontally centered, inset from the frame edges by `inset`
    /// (fraction of frame width).
    ///
    /// `contentHeight` is how many normalized template units tall the
    /// content actually is — pass the active template's max zone `y`
    /// (`RiftboundPlaymatTemplate.singlePlayerZones()`'s Hand zone
    /// currently extrapolates to `y ≈ 1.34`, past the quad's own `y = 1`
    /// bottom edge; see its doc comment). Defaulting this to `1.0` would
    /// place the quad's bottom edge near the frame's bottom margin same
    /// as before, but then Hand's extrapolated portion falls below the
    /// visible frame entirely before the user has dragged anything. Instead
    /// this shrinks the quad (and pushes it toward the top of the frame)
    /// so the *whole* `0...contentHeight` range fits on screen by default.
    public static func centered(in imageSize: CGSize, inset: CGFloat = 0.1, contentHeight: CGFloat = 1.0) -> PlaymatCalibration {
        let marginX = imageSize.width * inset
        let marginY = imageSize.height * inset
        let availableHeight = max(imageSize.height - 2 * marginY, 1)
        let quadHeight = availableHeight / contentHeight
        let quadBottomY = marginY + quadHeight

        return PlaymatCalibration(
            topLeft: CGPoint(x: marginX, y: marginY),
            topRight: CGPoint(x: imageSize.width - marginX, y: marginY),
            bottomRight: CGPoint(x: imageSize.width - marginX, y: quadBottomY),
            bottomLeft: CGPoint(x: marginX, y: quadBottomY)
        )
    }

    /// Maps a normalized template point (`x`/`y` in 0...1) into this
    /// calibration's quad via bilinear interpolation of the 4 corners.
    /// Not a full perspective (homography) transform — bilinear is simpler
    /// (no matrix inversion) and accurate enough for a roughly-overhead
    /// table camera without extreme perspective distortion. Revisit with
    /// a real homography only if testing against an actual angled camera
    /// shows this isn't good enough.
    public func map(_ normalized: CGPoint) -> CGPoint {
        let top = lerp(topLeft, topRight, normalized.x)
        let bottom = lerp(bottomLeft, bottomRight, normalized.x)
        return lerp(top, bottom, normalized.y)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// The calibrated mat's own boundary, corners in order — this is what
    /// "object detection should only focus on the segmented area" is
    /// built on: everything outside this quad is off-mat and should never
    /// even be handed to the detector.
    public var boundingPolygon: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Axis-aligned bounding box of `boundingPolygon` — cheap to intersect
    /// against, and what `VisionRectangleDetector`'s `regionOfInterest`
    /// actually needs (Vision's API takes a rect, not an arbitrary quad).
    public var boundingRect: CGRect {
        let xs = boundingPolygon.map(\.x)
        let ys = boundingPolygon.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    /// Every zone in `template`, mapped through this calibration into real
    /// pixel-space `BoardZone`s — feed the result straight to `ZoneMapper`.
    /// Defaults to the single-player mat layout (`RiftboundPlaymatTemplate
    /// .singlePlayerZones()`), which is the one currently in active use.
    /// Each zone carries its own `battlefieldSlot` now (see
    /// `PlaymatZoneTemplate`) rather than one slot applied to every
    /// Battlefield zone — this mat has two independent Battlefield
    /// regions, which a single external slot couldn't disambiguate.
    public func boardZones(template: [PlaymatZoneTemplate] = RiftboundPlaymatTemplate.singlePlayerZones()) -> [BoardZone] {
        template.map { zoneTemplate in
            BoardZone(
                type: zoneTemplate.zone,
                polygon: zoneTemplate.normalizedPolygon.map(map),
                owner: zoneTemplate.owner,
                battlefieldSlot: zoneTemplate.battlefieldSlot
            )
        }
    }
}
