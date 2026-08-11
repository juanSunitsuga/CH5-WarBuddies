import SwiftUI
import RiftboundVision

/// Right-hand sidebar: every recognized card in the *current* detection
/// poll, tap for real printed info (`CardDetailView`). Deliberately just
/// a live view of `pipeline.detections` — this architecture has no
/// persistent per-object identity (see `CameraPipelineController`'s doc
/// comment), so there's no stable "row" to track across polls the way
/// the old tracked-pipeline sidebar had. The list simply refreshes every
/// ~0.35s along with detection itself, and can show the same card twice
/// if it's genuinely detected twice in one frame (two physical copies on
/// the table, or a momentary double-detection) — no dedup logic tries to
/// paper over that, since without tracking there's no principled way to
/// tell those two cases apart.
struct DetectedCardsPanel: View {
    @ObservedObject var pipeline: CameraPipelineController
    @State private var detailPrinting: CardPrinting?

    /// Runes are excluded — this panel is specifically about card
    /// identity/text lookup, same scope as the tracked-pipeline sidebar
    /// it replaces.
    private var recognizedCards: [(detection: Detection, printing: CardPrinting)] {
        pipeline.detections
            .filter { $0.type == .card }
            .compactMap { detection in
                guard let label = detection.recognizedLabel,
                      let printing = pipeline.cardDatabase.printing(approximatelyNamed: label) else {
                    return nil
                }
                return (detection, printing)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("DETECTED CARDS")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))

                if recognizedCards.isEmpty {
                    Text("No cards recognized right now")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    ForEach(Array(recognizedCards.enumerated()), id: \.offset) { _, entry in
                        row(for: entry)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(.black.opacity(0.85))
        .sheet(item: $detailPrinting) { printing in
            CardDetailView(printing: printing, onClose: { detailPrinting = nil })
        }
    }

    private func row(for entry: (detection: Detection, printing: CardPrinting)) -> some View {
        Button {
            detailPrinting = entry.printing
        } label: {
            HStack(spacing: 8) {
                thumbnail(for: entry.printing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.printing.name)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(Int((entry.detection.confidence * 100).rounded()))% confidence")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(6)
            .background(.white.opacity(0.06))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(for printing: CardPrinting) -> some View {
        if let url = printing.media.imageURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 32, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 32, height: 44)
        }
    }
}
