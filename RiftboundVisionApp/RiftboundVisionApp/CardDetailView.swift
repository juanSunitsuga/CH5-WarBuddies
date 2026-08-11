import SwiftUI
import RiftboundVision

/// "Info" panel for a tracked card — printed stats and rules text pulled
/// straight from `CardPrinting` (real card data, per the brief: no
/// invented "best use case" commentary, just what's actually printed on
/// the card).
struct CardDetailView: View {
    let printing: CardPrinting
    let onClose: () -> Void
    /// `nil` when there's nothing to pay (no Energy cost, e.g. a Rune or a
    /// 0-cost card) — omits the button entirely rather than showing a
    /// disabled one with no useful cost to display.
    var onPlay: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(printing.name).font(.title2.bold())
                Spacer()
                if let onPlay, let energy = printing.attributes.energy, energy > 0 {
                    Button {
                        onPlay()
                    } label: {
                        Label("Play — Exhaust \(energy) Rune\(energy == 1 ? "" : "s")", systemImage: "bolt.fill")
                    }
                }
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: printing.media.imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2))
                }
                .frame(width: 180, height: 251)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 8) {
                    Text(printing.classification.type)
                        .font(.headline)
                    if let supertype = printing.classification.supertype {
                        Text(supertype).font(.subheadline).foregroundStyle(.secondary)
                    }

                    statsRow

                    if !printing.classification.domain.isEmpty {
                        Text(printing.classification.domain.joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let rarity = printing.classification.rarity {
                        Text(rarity).font(.caption).foregroundStyle(.secondary)
                    }

                    Divider()

                    Text(printing.text.plain.isEmpty ? "(No printed rules text)" : printing.text.plain)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let flavour = printing.text.flavour, !flavour.isEmpty {
                        Text(flavour)
                            .font(.callout.italic())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(printing.set.label) · #\(printing.collectorNumber.map(String.init) ?? "?") · \(printing.riftboundID)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 340)
    }

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 16) {
            if let energy = printing.attributes.energy {
                Label("\(energy)", systemImage: "bolt.fill")
            }
            if let might = printing.attributes.might {
                Label("\(might)", systemImage: "shield.fill")
            }
            if let power = printing.attributes.power {
                Label("\(power)", systemImage: "sparkles")
            }
        }
        .font(.callout)
    }
}
