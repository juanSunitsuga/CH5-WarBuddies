import Vision
import CoreGraphics

/// Converts a Vision observation's bounding box into pixel space.
///
/// The subtlety this exists to get right: when a request carries a
/// `regionOfInterest`, Vision reports observations **normalized to that
/// region**, not to the whole image. Multiplying such a box by the full
/// image size — which is what this layer did when region-of-interest
/// scanning was first introduced — squashes every detection toward the
/// origin, so boxes and tracked centroids stop landing on the cards.
///
/// A free function purely so the arithmetic is testable without a camera
/// or a Core ML model behind it.
///
/// - Parameters:
///   - normalizedBox: Vision's box, origin bottom-left, relative to
///     `visionRegionOfInterest`.
///   - visionRegionOfInterest: the request's region in Vision's own
///     normalized, origin-bottom-left space. Pass the full unit rect when
///     no region was set.
///   - imageSize: pixel dimensions of the source image.
/// - Returns: a rect in pixel space, origin top-left, matching
///   `Detection.boundingBox`'s convention.
public func imageRect(
    fromNormalized normalizedBox: CGRect,
    visionRegionOfInterest: CGRect,
    imageSize: CGSize
) -> CGRect {
    // Lift the ROI-relative box back into whole-image normalized space.
    let originX = visionRegionOfInterest.minX + normalizedBox.minX * visionRegionOfInterest.width
    let originY = visionRegionOfInterest.minY + normalizedBox.minY * visionRegionOfInterest.height
    let width = normalizedBox.width * visionRegionOfInterest.width
    let height = normalizedBox.height * visionRegionOfInterest.height

    // Vision's origin is bottom-left; `Detection` uses top-left.
    return CGRect(
        x: originX * imageSize.width,
        y: (1 - originY - height) * imageSize.height,
        width: width * imageSize.width,
        height: height * imageSize.height
    )
}

/// A pixel-space rect converted into Vision's normalized,
/// origin-bottom-left convention, clamped to the unit square.
public func visionRegion(from pixelRect: CGRect, imageSize: CGSize) -> CGRect {
    CGRect(
        x: pixelRect.minX / imageSize.width,
        y: 1 - (pixelRect.minY + pixelRect.height) / imageSize.height,
        width: pixelRect.width / imageSize.width,
        height: pixelRect.height / imageSize.height
    ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
}

/// Abstracts detection so tracking/temporal-confirmation code never needs
/// real Vision/CoreML to be testable. Per the brief: do NOT train an
/// action classifier yet, and don't require this to identify the exact
/// card — it only answers CARD / RUNE / UNKNOWN.
public protocol ObjectDetecting: Sendable {
    /// `regionOfInterest`, if given, is in the same pixel-space coordinate
    /// convention as `Detection.center`/`.boundingBox` (origin top-left,
    /// matching `TrackedObject`) — implementations convert into whatever
    /// their underlying detector actually expects. Passing the calibrated
    /// playmat's bounding rect here is what "object detection should only
    /// focus on the segmented area" means in practice: nothing outside it
    /// is even handed to the underlying detector, let alone tracked.
    func detect(in pixelBuffer: CVPixelBuffer, regionOfInterest: CGRect?) throws -> [Detection]
}

extension ObjectDetecting {
    public func detect(in pixelBuffer: CVPixelBuffer) throws -> [Detection] {
        try detect(in: pixelBuffer, regionOfInterest: nil)
    }
}

/// A deliberately simple, non-ML starting point: Vision's built-in
/// rectangle detector finds card/rune-shaped quadrilaterals, and aspect
/// ratio is used as a coarse CARD-vs-RUNE heuristic (Riftbound cards and
/// runes ship at different long-edge/short-edge ratios). This is a
/// placeholder, explicitly not a trained classifier — replace with a real
/// CoreML model per-object only once the deterministic pipeline
/// (tracking + zones + temporal confirmation) has a demonstrated failure
/// case this can't resolve, per the brief's "don't introduce ML before
/// there's a demonstrated need" guidance.
public struct VisionRectangleDetector: ObjectDetecting {
    /// Card long/short edge ratio is taller/narrower than a typical Rune
    /// token; tune both bounds against your actual physical cards/runes
    /// during calibration.
    public var cardAspectRatioRange: ClosedRange<CGFloat>
    public var minimumConfidence: VNConfidence

    public init(cardAspectRatioRange: ClosedRange<CGFloat> = 1.3...1.6, minimumConfidence: VNConfidence = 0.7) {
        self.cardAspectRatioRange = cardAspectRatioRange
        self.minimumConfidence = minimumConfidence
    }

    public func detect(in pixelBuffer: CVPixelBuffer, regionOfInterest: CGRect? = nil) throws -> [Detection] {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = minimumConfidence
        request.maximumObservations = 40
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        // Vision search is restricted to this region, which is both a real
        // speedup (less area to scan) and the mechanism that keeps clutter
        // off the mat from ever becoming a `Detection`. Kept so results can
        // be mapped back — Vision reports observations relative to the
        // region, not the whole image.
        var visionROI = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let regionOfInterest {
            visionROI = visionRegion(from: regionOfInterest, imageSize: CGSize(width: width, height: height))
            request.regionOfInterest = visionROI
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let detections = (request.results ?? []).map { observation -> Detection in
            // Vision's normalized (0...1, origin bottom-left) coordinates
            // → pixel space, origin top-left, matching `TrackedObject`'s
            // camera-space convention used elsewhere in this layer.
            let rect = imageRect(
                fromNormalized: observation.boundingBox,
                visionRegionOfInterest: visionROI,
                imageSize: CGSize(width: width, height: height)
            )
            let aspectRatio = max(rect.width, rect.height) / max(min(rect.width, rect.height), 1)
            let type: ObjectType = cardAspectRatioRange.contains(aspectRatio) ? .card : .unknown

            let dx = observation.topRight.x - observation.topLeft.x
            let dy = observation.topRight.y - observation.topLeft.y
            let rotation = atan2(dy, dx)

            return Detection(
                type: type,
                center: CGPoint(x: rect.midX, y: rect.midY),
                boundingBox: rect,
                rotation: rotation,
                confidence: observation.confidence
            )
        }

        // Belt-and-suspenders: `regionOfInterest` is a search hint, not a
        // hard guarantee every returned observation's centroid falls
        // inside it (a rectangle straddling the edge can still be
        // reported). Drop anything whose center isn't actually on-mat.
        guard let regionOfInterest else { return detections }
        return detections.filter { regionOfInterest.contains($0.center) }
    }
}
