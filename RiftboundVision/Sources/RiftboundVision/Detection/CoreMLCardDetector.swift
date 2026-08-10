import Vision
import CoreML
import CoreGraphics

/// Real per-card detection, backed by a trained YOLO object-detection
/// model exported to Core ML (see `RiftboundVisionApp/Resources/
/// CardDetectionModel/best.mlpackage` — Ultralytics YOLO11n, 38 classes
/// covering the Annie and Garen proving-ground decks' cards and basic
/// Runes; trained 2026-08-09, `mAP`/accuracy not independently verified
/// here). Unlike `VisionRectangleDetector`, this identifies *which* card
/// a detection is, not just CARD-vs-RUNE — the class label comes straight
/// through on `Detection.recognizedLabel`.
///
/// KNOWN LIMITATION: YOLO object detection gives axis-aligned bounding
/// boxes only — there is no oriented/rotated-rectangle signal the way
/// `VNDetectRectanglesRequest` provides. Every `Detection.rotation` this
/// emits is `0`, which means `TemporalEventDetector`'s Exhaust/Ready
/// signature (rules 592–593) cannot be derived from this detector's
/// output alone. Don't silently lose that capability — either keep
/// running `VisionRectangleDetector` in parallel for rotation, or accept
/// Exhaust/Ready detection is not covered until this model (or a second
/// pass) supplies orientation.
/// `@unchecked Sendable`: `VNCoreMLModel` isn't Sendable-annotated, but
/// Apple documents Vision request/model objects as safe to reuse across
/// concurrent requests — matches the `@unchecked Sendable` pattern already
/// used elsewhere in this layer (`AVFoundationCameraCapture`, etc.) for
/// the same reason.
public struct CoreMLCardDetector: ObjectDetecting, @unchecked Sendable {
    private let visionModel: VNCoreMLModel
    public var minimumConfidence: VNConfidence

    /// - Parameters:
    ///   - model: a loaded `MLModel` — the caller owns loading it from
    ///     wherever it's bundled (e.g. `Bundle.main.url(forResource:
    ///     "best", withExtension: "mlmodelc")`), same seam
    ///     `CardDatabaseLoader` uses for the bundled deck JSON. Keeping
    ///     this library model-agnostic (a plain `MLModel`, not a hardcoded
    ///     resource name) means it isn't tied to one specific bundle.
    ///   - minimumConfidence: per-detection confidence floor, applied on
    ///     top of whatever threshold is already baked into the model's
    ///     NMS (0.25 for the bundled model — see its metadata).
    public init(model: MLModel, minimumConfidence: VNConfidence = 0.4) throws {
        self.visionModel = try VNCoreMLModel(for: model)
        self.minimumConfidence = minimumConfidence
    }

    public func detect(in pixelBuffer: CVPixelBuffer, regionOfInterest: CGRect? = nil) throws -> [Detection] {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        if let regionOfInterest {
            // Same pixel-space → Vision-normalized conversion as
            // `VisionRectangleDetector` — see its doc comment.
            request.regionOfInterest = CGRect(
                x: regionOfInterest.minX / width,
                y: 1 - (regionOfInterest.minY + regionOfInterest.height) / height,
                width: regionOfInterest.width / width,
                height: regionOfInterest.height / height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []

        let detections = observations.compactMap { observation -> Detection? in
            guard let topLabel = observation.labels.first, topLabel.confidence >= minimumConfidence else {
                return nil
            }

            let box = observation.boundingBox
            let rect = CGRect(
                x: box.origin.x * width,
                y: (1 - box.origin.y - box.height) * height,
                width: box.width * width,
                height: box.height * height
            )

            // The bundled model's class names are literally "<X> Rune"
            // for the 4 basic-Rune classes (see its embedded metadata);
            // everything else is a Main Deck/Legend card.
            let isRune = topLabel.identifier.hasSuffix(" Rune")

            return Detection(
                type: isRune ? .rune : .card,
                center: CGPoint(x: rect.midX, y: rect.midY),
                boundingBox: rect,
                rotation: 0, // see this type's KNOWN LIMITATION doc comment
                confidence: topLabel.confidence,
                recognizedLabel: topLabel.identifier
            )
        }

        guard let regionOfInterest else { return detections }
        return detections.filter { regionOfInterest.contains($0.center) }
    }
}
