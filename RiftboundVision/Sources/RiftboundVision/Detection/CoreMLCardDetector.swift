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
    /// Class labels the model can emit that aren't real cards, and should
    /// be dropped rather than tracked. Empty by default — "Token" is a real
    /// Riftbound card class (a spawned unit token, e.g. "Sprite unit
    /// token"), not a hard negative, so it's tracked and saved like any
    /// other card.
    public var nonCardLabels: Set<String>
    /// `max(width, height) / min(width, height)` of an accepted detection
    /// — every Riftbound card (including Rune cards; they're the same
    /// physical card stock) ships at roughly 2.5"×3.5", a ~1.4 long/short
    /// ratio, regardless of which way it's rotated. A near-square box
    /// (ratio ≈ 1) is a real object the model mistook for one of its 38
    /// known classes, not an actual card, however high its confidence —
    /// this is what "every square object gets identified" was: the model
    /// alone has no shape prior, only `minimumConfidence` was gating it,
    /// and a small-class-count model can be confidently wrong. Matches
    /// `VisionRectangleDetector.cardAspectRatioRange`'s convention, widened
    /// a bit since YOLO's axis-aligned boxes are less tightly fit than
    /// Vision's oriented rectangle detector.
    public var cardAspectRatioRange: ClosedRange<CGFloat>

    /// - Parameters:
    ///   - model: a loaded `MLModel` — the caller owns loading it from
    ///     wherever it's bundled (e.g. `Bundle.main.url(forResource:
    ///     "best", withExtension: "mlmodelc")`), same seam
    ///     `CardDatabaseLoader` uses for the bundled deck JSON. Keeping
    ///     this library model-agnostic (a plain `MLModel`, not a hardcoded
    ///     resource name) means it isn't tied to one specific bundle.
    ///   - minimumConfidence: per-detection confidence floor, applied on
    ///     top of whatever threshold is already baked into the model's
    ///     own NMS (0.25 for the bundled model — see its metadata, a lot
    ///     looser than this). Defaulted well above that: a wrongly-boxed
    ///     background object clearing 0.25 is common with only 38 trained
    ///     classes; requiring 0.75 cuts most of that out before the shape
    ///     check below even runs.
    ///   - cardAspectRatioRange: see this property's own doc comment.
    public init(
        model: MLModel,
        minimumConfidence: VNConfidence = 0.75,
        cardAspectRatioRange: ClosedRange<CGFloat> = 1.2...1.8,
        nonCardLabels: Set<String> = []
    ) throws {
        self.visionModel = try VNCoreMLModel(for: model)
        self.minimumConfidence = minimumConfidence
        self.nonCardLabels = nonCardLabels
        self.cardAspectRatioRange = cardAspectRatioRange
    }

    public func detect(in pixelBuffer: CVPixelBuffer, regionOfInterest: CGRect? = nil) throws -> [Detection] {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let request = VNCoreMLRequest(model: visionModel)
        // Must match how training images were prepared, or every card is
        // fed to the model warped in a way it never trained on. Both the v2
        // and v3 Roboflow exports say "Resize to 640x640 (Fit (black
        // edges))" — letterboxed, aspect ratio preserved. `.scaleFill`
        // stretches non-uniformly to fill the square input, which is the
        // wrong one; `.scaleFit` preserves aspect ratio and matches the
        // letterbox the model actually saw.
        request.imageCropAndScaleOption = .scaleFit

        // Kept so results can be mapped back: Vision reports observations
        // relative to this region, not to the whole image.
        var visionROI = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let regionOfInterest {
            visionROI = visionRegion(from: regionOfInterest, imageSize: CGSize(width: width, height: height))
            request.regionOfInterest = visionROI
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []

        let detections = observations.compactMap { observation -> Detection? in
            guard let topLabel = observation.labels.first, topLabel.confidence >= minimumConfidence else {
                return nil
            }
            // A hard-negative class is a statement that this *isn't* a
            // card — the most useful thing the model can say about clutter.
            guard !nonCardLabels.contains(topLabel.identifier) else { return nil }

            let rect = imageRect(
                fromNormalized: observation.boundingBox,
                visionRegionOfInterest: visionROI,
                imageSize: CGSize(width: width, height: height)
            )

            // Reject anything that isn't card-shaped regardless of
            // confidence — see `cardAspectRatioRange`'s doc comment.
            let aspectRatio = max(rect.width, rect.height) / max(min(rect.width, rect.height), 1)
            guard cardAspectRatioRange.contains(aspectRatio) else { return nil }

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
