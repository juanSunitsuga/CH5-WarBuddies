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
    /// centered, inset from the frame edges by `inset` (fraction of the
    /// smaller dimension).
    public static func centered(in imageSize: CGSize, inset: CGFloat = 0.1) -> PlaymatCalibration {
        let margin = min(imageSize.width, imageSize.height) * inset
        return PlaymatCalibration(
            topLeft: CGPoint(x: margin, y: margin),
            topRight: CGPoint(x: imageSize.width - margin, y: margin),
            bottomRight: CGPoint(x: imageSize.width - margin, y: imageSize.height - margin),
            bottomLeft: CGPoint(x: margin, y: imageSize.height - margin)
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

    /// Every template zone, mapped through this calibration into real
    /// pixel-space `BoardZone`s — feed the result straight to `ZoneMapper`.
    /// `battlefieldSlot` is a single value because this template models
    /// one shared Battlefield band; a physical mat with multiple distinct
    /// Battlefield spaces would need per-region slots, which this
    /// single-quad calibration doesn't attempt to disambiguate.
    public func boardZones(battlefieldSlot: Int = 0) -> [BoardZone] {
        RiftboundPlaymatTemplate.zones.map { template in
            BoardZone(
                type: template.zone,
                polygon: template.normalizedPolygon.map(map),
                owner: template.owner,
                battlefieldSlot: template.zone == .battlefield ? battlefieldSlot : nil
            )
        }
    }
}
