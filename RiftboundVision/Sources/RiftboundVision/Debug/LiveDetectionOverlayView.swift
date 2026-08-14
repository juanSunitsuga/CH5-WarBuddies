import SwiftUI

/// Draws a colored bracket + label for every current detection — the
/// live "what does the detector see right now" overlay. Deliberately
/// stateless: no persistent identity, no zone, no rotation, nothing
/// carried across frames. Ported from
/// `feature/riftbound-scanner-prototype`'s `PlaymatOverlayView` live
/// detection layer to match its architecture — `CameraPipelineController`
/// republishes a completely fresh `[Detection]` array on every detection
/// poll (see its doc comment), so there's nothing to reconcile between
/// frames; this view just draws whatever it's handed.
public struct LiveDetectionOverlayView: View {
    let detections: [Detection]
    /// Resolves a detection's real printed name (e.g. "Garen - Rugged")
    /// via a fresh, uncached `cardDatabase` lookup each time this view
    /// redraws — matching the prototype's stateless per-poll
    /// `CardDatabase.shared.card(for:)`. `nil` skips the lookup entirely
    /// and falls back to the detector's raw class label.
    let cardDatabase: CardDatabase?

    /// Confidence at/above this reads green ("recognized"); below reads
    /// orange ("detected but not confidently recognized"). Everything
    /// drawn here already cleared `CoreMLCardDetector.minimumConfidence`
    /// and its card-shape gate, so this is purely a display distinction,
    /// not a second filter.
    private static let recognizedThreshold: Float = 0.75

    public init(detections: [Detection], cardDatabase: CardDatabase? = nil) {
        self.detections = detections
        self.cardDatabase = cardDatabase
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(detections.enumerated()), id: \.offset) { _, detection in
                box(for: detection)
            }
        }
    }

    @ViewBuilder
    private func box(for detection: Detection) -> some View {
        let box = detection.boundingBox
        let color: Color = detection.confidence >= Self.recognizedThreshold ? .green : .orange

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(color, lineWidth: 3)
            .shadow(color: color.opacity(0.7), radius: 6)
            .frame(width: max(box.width, 1), height: max(box.height, 1))
            .position(x: box.midX, y: box.midY)
            .overlay(alignment: .topLeading) {
                label(for: detection, color: color)
                    .position(x: box.minX + 4, y: box.minY - 14)
            }
    }

    private func label(for detection: Detection, color: Color) -> some View {
        // Prefer the real printed card name from `cardDatabase`; fall
        // back to the detector's raw class label, then the coarse
        // `.card`/`.rune` type — which reads identically for every card
        // of the same object type, so it's the last resort.
        let recognizedName = detection.recognizedLabel.flatMap { cardDatabase?.printing(approximatelyNamed: $0)?.name }
        let name = recognizedName ?? detection.recognizedLabel ?? detection.type.rawValue
        // No percentage. The detector re-scores every card several times a
        // second, so a live figure churned constantly for a card lying
        // perfectly still — motion that reads as instability rather than
        // information. Confidence still drives the colour, which conveys
        // "recognized" vs "unsure" without the flicker.
        return Text(name)
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.gradient, in: Capsule())
            .fixedSize()
    }
}
