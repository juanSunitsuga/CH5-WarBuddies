import CoreML
import RiftboundVision

/// Loads the bundled trained card-detection model
/// (`Resources/CardDetectionModel/best-2.mlpackage` — Ultralytics YOLO11n
/// trained on the v3 Roboflow export (`dataset roboflow/
/// Riftbound-Card-Detection-2`, 1,208 source images against the original
/// v2 export's 393), 39 classes: the original 38 real cards plus "Token"
/// for the spawned-unit proxy card. `best.mlpackage`/`best-3.mlpackage`
/// stay bundled for comparison but are no longer loaded — `best-3` is a
/// later checkpoint from the same training run with no recorded
/// validation numbers in this repo to justify preferring it over
/// `best-2`) and wraps it as a `CoreMLCardDetector`, which tracks the
/// "Token" class rather than dropping it — see `CoreMLCardDetector`'s
/// `nonCardLabels` doc comment.
enum CardDetectionModelLoader {
    /// Falls back to `VisionRectangleDetector` (the geometric heuristic —
    /// finds CARD/RUNE-shaped rectangles but never identifies *which*
    /// card) if the model is missing or fails to load, so the app keeps
    /// working with degraded (unidentified) tracking rather than
    /// crashing at launch.
    static func loadDetector() -> any ObjectDetecting {
        guard let url = Bundle.main.url(forResource: "best-2", withExtension: "mlmodelc") else {
            print("CardDetectionModelLoader: best-2.mlmodelc not found in the app bundle — falling back to VisionRectangleDetector (no card identity).")
            return VisionRectangleDetector()
        }
        do {
            let model = try MLModel(contentsOf: url)
            return try CoreMLCardDetector(model: model)
        } catch {
            print("CardDetectionModelLoader: failed to load best-2.mlmodelc (\(error)) — falling back to VisionRectangleDetector.")
            return VisionRectangleDetector()
        }
    }
}
