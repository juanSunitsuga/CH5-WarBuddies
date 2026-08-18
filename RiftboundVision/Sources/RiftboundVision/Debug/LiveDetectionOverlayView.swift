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
    /// Which card is currently selected, so its box can be highlighted.
    /// Matched by printing id rather than by detection: detections carry no
    /// identity across polls, so anything keyed to one would flicker.
    var selectedPrintingID: String?
    /// Called when a box is tapped, with the card it resolved to. `nil`
    /// makes the overlay non-interactive, which is what previews and the
    /// unidentified-detector path want.
    var onSelect: ((CardPrinting) -> Void)?

    /// Confidence at/above this reads green ("recognized"); below reads
    /// orange ("detected but not confidently recognized"). Everything
    /// drawn here already cleared `CoreMLCardDetector.minimumConfidence`
    /// and its card-shape gate, so this is purely a display distinction,
    /// not a second filter.
    private static let recognizedThreshold: Float = 0.75

    public init(
        detections: [Detection],
        cardDatabase: CardDatabase? = nil,
        selectedPrintingID: String? = nil,
        onSelect: ((CardPrinting) -> Void)? = nil
    ) {
        self.detections = detections
        self.cardDatabase = cardDatabase
        self.selectedPrintingID = selectedPrintingID
        self.onSelect = onSelect
    }

    /// The catalogue entry behind a detection, if it was recognized.
    private func printing(for detection: Detection) -> CardPrinting? {
        detection.recognizedLabel.flatMap { cardDatabase?.printing(approximatelyNamed: $0) }
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
        let card = printing(for: detection)
        let isSelected = card != nil && card?.id == selectedPrintingID
        // Was cyan/green/orange — three hues from nowhere on the design
        // board, sitting directly on top of the one part of the window a
        // player actually looks at. The palette has no traffic-light
        // triple, so the distinction is carried by value instead: bright
        // gold for the selected card, the mat's own gold for a confident
        // read, and the neutral disabled stroke for an unsure one, which
        // reads as "the app isn't committing to this" without inventing a
        // warning colour.
        let color: Color = isSelected
            ? PlaymatPalette.highlightOverlay
            : (detection.confidence >= Self.recognizedThreshold
                ? PlaymatPalette.playmatOverlay
                : PlaymatPalette.disabledElementStroke)

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(color, lineWidth: isSelected ? 6 : 3)
            .shadow(color: color.opacity(0.7), radius: isSelected ? 12 : 6)
            // The stroke alone is only hit-testable on the line itself; a
            // filled, near-transparent shape makes the whole card tappable.
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(isSelected ? 0.18 : 0.001)))
            .frame(width: max(box.width, 1), height: max(box.height, 1))
            .position(x: box.midX, y: box.midY)
            .onTapGesture {
                guard let card else { return }
                onSelect?(card)
            }
            .overlay(alignment: .topLeading) {
                label(for: detection, color: color)
                    .position(x: box.minX + 4, y: box.minY - 14)
                    .allowsHitTesting(false)
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
        // 32pt for the same reason the zone labels are 24: this is drawn
        // in camera-frame pixel space and scaled down to fit the window,
        // so it isn't a screen-point size and the 15pt body size doesn't
        // apply. The capsule is a flat `elementShadow` fill rather than a
        // gradient of the box colour — the gradient made two adjacent
        // labels look like different states when they weren't.
        return Text(name)
            .font(.custom("Sora-Bold", size: 32))
            .foregroundStyle(PlaymatPalette.regularText)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PlaymatPalette.elementShadow, in: Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 2))
            .fixedSize()
    }
}
