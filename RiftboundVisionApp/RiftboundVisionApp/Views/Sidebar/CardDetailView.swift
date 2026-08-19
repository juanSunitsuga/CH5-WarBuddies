import SwiftUI
import RiftboundVision

/// "Info" panel for a detected card — printed stats and rules text pulled
/// straight from `CardPrinting` (real card data, per the brief: no
/// invented "best use case" commentary, just what's actually printed on
/// the card).
///
/// No call sites remain — the Card Library column in `DetectedCardsPanel`
/// took over card inspection. Themed rather than deleted, since removing a
/// file is a decision about the project, not the front end; it is dead
/// code as it stands.
struct CardDetailView: View {
    let printing: CardPrinting
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(printing.name)
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(RiftSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 16) {
                CardArtView(printing: printing)
                    .frame(width: 180, height: 251)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(printing.classification.type)
                        .font(RiftboundFont.heading)
                        .foregroundStyle(RiftboundPalette.regularText)
                    if let supertype = printing.classification.supertype {
                        Text(supertype)
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
                    }

                    statsRow

                    if !printing.classification.domain.isEmpty {
                        Text(printing.classification.domain.joined(separator: " / "))
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
                    }

                    if let rarity = printing.classification.rarity {
                        Text(rarity)
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
                    }

                    Rectangle()
                        .fill(RiftboundPalette.elementStroke.opacity(0.4))
                        .frame(height: 1)

                    Text(printing.text.plain.isEmpty ? "(No printed rules text)" : printing.text.plain)
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let flavour = printing.text.flavour, !flavour.isEmpty {
                        Text(flavour)
                            .font(RiftboundFont.body)
                            .italic()
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
                    }

                    Spacer()

                    Text("\(printing.set.label) · #\(printing.collectorNumber.map(String.init) ?? "?") · \(printing.riftboundID)")
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.45))
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 340)
        .background(RiftboundPalette.secondaryBackground)
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
        .font(RiftboundFont.body)
        .foregroundStyle(RiftboundPalette.highlightOverlay)
    }
}
