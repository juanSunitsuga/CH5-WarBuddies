import CoreML
import RiftboundVision

/// Loads the bundled trained card-detection model
/// (`Resources/CardDetectionModel/best-4.mlpackage` — Ultralytics YOLO11n,
/// exported 2026-08-19) and wraps it as a `CoreMLCardDetector`, which
/// tracks the "Token" class rather than dropping it — see
/// `CoreMLCardDetector`'s `nonCardLabels` doc comment.
///
/// Drop-in compatible with the `best-2` it replaces, verified against both
/// models' embedded metadata rather than assumed: the same 39 classes in
/// the same order (so class 33 is still "Token", and `class_map.json`
/// stays valid), the same 640×640 letterboxed input, and the same
/// baked-in NMS. Nothing downstream needed changing.
///
/// `best.mlpackage`/`best-2`/`best-3` stay bundled for comparison but are
/// no longer loaded. As with the earlier `best-2` vs `best-3` choice, this
/// repo records no validation numbers for any of them — `best-4` is
/// preferred here because it's the newest export, not because it's been
/// measured against the held-out test split.
enum CardDetectionModelLoader {
    /// The bundled model's resource name.
    ///
    /// The "Verify bundled Core ML model" build phase reads this exact
    /// line out of this file to know what to look for in the built bundle,
    /// so changing the model here also moves the build-time check — the
    /// guard can't be left behind pointing at a model nobody loads
    /// anymore. Keep it a plain string literal on one line.
    static let modelName = "best-4"

    /// A loaded detector, plus why it isn't the real one if it isn't.
    struct Result {
        let detector: any ObjectDetecting
        /// `nil` on the happy path. Non-`nil` means the trained model
        /// couldn't be loaded and the geometric fallback is in use, which
        /// the app surfaces on screen — see
        /// `CameraPipelineController.detectorFallbackWarning`.
        let fallbackReason: String?
    }

    /// Falls back to `VisionRectangleDetector` (the geometric heuristic —
    /// finds CARD/RUNE-shaped rectangles but never identifies *which*
    /// card) if the model is missing or fails to load, so the app keeps
    /// working with degraded (unidentified) tracking rather than
    /// crashing at launch.
    ///
    /// The fallback used to be silent — a `print` nobody reads when
    /// launching from Xcode — which is what made the build-phase mistake
    /// this model arrived with so easy to miss: an `.mlpackage` added to
    /// *Compile Sources* rather than *Copy Bundle Resources* is never
    /// compiled to `.mlmodelc` or copied, so this lookup fails and the app
    /// runs with no card identity at all while looking like it works. It
    /// has happened twice in this project now. Two things catch it: the
    /// build phase named above fails the build outright, and
    /// `fallbackReason` puts it on screen if a build ever gets past that.
    static func loadDetector() -> Result {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            let reason = "\(modelName).mlmodelc isn't in the app bundle, so cards can be located but not identified. The .mlpackage is probably in the target's Compile Sources build phase instead of Copy Bundle Resources."
            print("CardDetectionModelLoader: \(reason)")
            return Result(detector: VisionRectangleDetector(), fallbackReason: reason)
        }
        do {
            let model = try MLModel(contentsOf: url)
            return Result(detector: try CoreMLCardDetector(model: model), fallbackReason: nil)
        } catch {
            let reason = "\(modelName).mlmodelc is bundled but failed to load (\(error)), so cards can be located but not identified."
            print("CardDetectionModelLoader: \(reason)")
            return Result(detector: VisionRectangleDetector(), fallbackReason: reason)
        }
    }
}
