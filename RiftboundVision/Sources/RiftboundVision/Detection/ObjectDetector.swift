import Vision
import CoreGraphics

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
        if let regionOfInterest {
            // Vision search is restricted to this region, which is both a
            // real speedup (less area to scan) and the mechanism that
            // keeps background clutter off the mat from ever becoming a
            // `Detection` at all. Convert pixel-space (origin top-left) →
            // Vision's normalized, origin-bottom-left convention.
            request.regionOfInterest = CGRect(
                x: regionOfInterest.minX / width,
                y: 1 - (regionOfInterest.minY + regionOfInterest.height) / height,
                width: regionOfInterest.width / width,
                height: regionOfInterest.height / height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let detections = (request.results ?? []).map { observation -> Detection in
            // Vision's normalized (0...1, origin bottom-left) coordinates
            // → pixel space, origin top-left, matching `TrackedObject`'s
            // camera-space convention used elsewhere in this layer.
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.origin.x * width,
                y: (1 - box.origin.y - box.height) * height,
                width: box.width * width,
                height: box.height * height
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
