import CoreML
import RiftboundVision

/// Loads the bundled trained card-detection model
/// (`Resources/CardDetectionModel/best.mlpackage`, pulled from the
/// `caca_base_scanner` branch — see its commit message for provenance:
/// Ultralytics YOLO11n, 38 classes covering the Annie and Garen decks)
/// and wraps it as a `CoreMLCardDetector`.
enum CardDetectionModelLoader {
    /// Falls back to `VisionRectangleDetector` (the geometric heuristic —
    /// finds CARD/RUNE-shaped rectangles but never identifies *which*
    /// card) if the model is missing or fails to load, so the app keeps
    /// working with degraded (unidentified) tracking rather than
    /// crashing at launch.
    static func loadDetector() -> any ObjectDetecting {
        guard let url = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") else {
            print("CardDetectionModelLoader: best.mlmodelc not found in the app bundle — falling back to VisionRectangleDetector (no card identity).")
            return VisionRectangleDetector()
        }
        do {
            let model = try MLModel(contentsOf: url)
            return try CoreMLCardDetector(model: model)
        } catch {
            print("CardDetectionModelLoader: failed to load best.mlmodelc (\(error)) — falling back to VisionRectangleDetector.")
            return VisionRectangleDetector()
        }
    }
}
