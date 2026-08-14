import CoreML
import RiftboundVision

/// Loads the bundled trained card-detection model
/// (`Resources/CardDetectionModel/best-2.mlpackage` — retrained on the v3
/// export, 1,208 source images against the original's 393, plus a "Token"
/// class that absorbs hard negatives which used to be confidently misread
/// as one of the 38 real cards) and wraps it as a `CoreMLCardDetector`,
/// which drops that class rather than tracking it. `best.mlpackage` stays
/// bundled for comparison but is no longer loaded.
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
