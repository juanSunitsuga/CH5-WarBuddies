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
    ///
    /// `aspectRatio` (width ÷ height of the *mat*, i.e. the `0...1` unit
    /// square) is what keeps the border artwork from stretching: the
    /// template's zones are sized from their PNGs' real pixel dimensions
    /// (see `RiftboundPlaymatTemplate.matAspectRatio`), so a quad with a
    /// different proportion would squash every frame drawn into it. Pass
    /// `nil` to fill the inset area regardless of proportion.
    public static func centered(
        in imageSize: CGSize,
        inset: CGFloat = 0.1,
        contentHeight: CGFloat = 1.0,
        aspectRatio: CGFloat? = RiftboundPlaymatTemplate.matAspectRatio
    ) -> PlaymatCalibration {
        let marginX = imageSize.width * inset
        let marginY = imageSize.height * inset
        let availableWidth = max(imageSize.width - 2 * marginX, 1)
        let availableHeight = max(imageSize.height - 2 * marginY, 1)

        // Fit the whole `0...contentHeight` range inside the inset area
        // without distortion: the quad itself is `0...1`, so the content
        // is `contentHeight` quads tall.
        var quadWidth = availableWidth
        var quadHeight = availableHeight / contentHeight
        if let aspectRatio, aspectRatio > 0 {
            quadHeight = min(quadHeight, quadWidth / aspectRatio)
            quadWidth = quadHeight * aspectRatio
        }

        let originX = (imageSize.width - quadWidth) / 2
        let originY = marginY

        return PlaymatCalibration(
            topLeft: CGPoint(x: originX, y: originY),
            topRight: CGPoint(x: originX + quadWidth, y: originY),
            bottomRight: CGPoint(x: originX + quadWidth, y: originY + quadHeight),
            bottomLeft: CGPoint(x: originX, y: originY + quadHeight)
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

    /// Region the detector should actually scan: every calibrated zone's
    /// extent, plus a margin.
    ///
    /// Not `boundingRect` — that's the calibration quad, and the Hand zone
    /// deliberately extends past its bottom edge (`y ≈ 1.34`) out onto the
    /// table. Scanning only the quad would make hand cards undetectable.
    ///
    /// Handing this to `ObjectDetecting.detect(in:regionOfInterest:)` is
    /// what "detection should only look at the mat" means in practice: the
    /// model sees a smaller image, so inference is cheaper *and* clutter
    /// off the mat can't become a `Detection` in the first place.
    ///
    /// - Parameter margin: fraction of the region's own size to expand by,
    ///   so a card overhanging a zone edge isn't clipped.
    public func detectionRegion(
        template: [PlaymatZoneTemplate] = RiftboundPlaymatTemplate.singlePlayerZones(),
        margin: CGFloat = 0.04
    ) -> CGRect {
        let points = template.flatMap(\.normalizedPolygon).map(map)
        guard !points.isEmpty else { return boundingRect }
        let xs = points.map(\.x), ys = points.map(\.y)
        let rect = CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
        return rect.insetBy(dx: -rect.width * margin, dy: -rect.height * margin)
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
