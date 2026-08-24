import SwiftUI
import RiftboundVision

/// The Card Library's full-page browse view — art, name, Type/Cost/Ability,
/// and a Description section, matching the "Card Details" hi-fi mockup.
///
/// Pure content, not a sheet of its own: `CardLibrarySheet` owns the popup's
/// frame, background and Back/Close header, and swaps this in for the
/// result list when a card is tapped, so browsing a card's details never
/// leaves the library's window. Deliberately *not* `InlineCardDetail` —
/// that one is sized to sit beside a thumbnail already on screen elsewhere
/// and omits the artwork for exactly that reason; here the art gets its own
/// full-width band at the top of the page.
struct CardDetailView: View {
    let printing: CardPrinting
    /// Rules text for `printing`, resolved by the caller (see
    /// `CameraPipelineController.description(for:)`) — the same
    /// simplified, first-timer-friendly text `InlineCardDetail` shows, so a
    /// card's Ability doesn't read differently depending on whether you
    /// found it through the strip or the library.
    let description: String

    /// How wide the info column (rows, Description, footer) reads best —
    /// text set to the full 480pt sheet width made "Give two friendly
    /// units each +2 Might for this turn." span nearly the whole page in
    /// one line, which doesn't read like a card. Centring a narrower
    /// column under the art is closer to how the physical card itself
    /// paces its own text.
    private static let infoColumnWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            // Battlefields print *landscape* — `CardOrientation`'s own doc
            // comment notes it as the one exception to every other type
            // being portrait. A fixed portrait frame around one just left
            // the art letterboxed inside a too-tall box; swapping the two
            // dimensions for a landscape printing keeps the same box area
            // without stretching or shrinking the art itself.
            CardArtView(printing: printing)
                .frame(width: artSize.width, height: artSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
                )

            Text(printing.name)
                .font(RiftboundFont.iconic2)
                .foregroundStyle(RiftboundPalette.iconicText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.infoColumnWidth)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    CardAttributeRow(label: "Type", value: printing.classification.type)
                    if let cost = printing.costLabel { CardAttributeRow(label: "Cost", value: cost) }
                    CardAttributeRow(label: "Ability", value: abilityText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(RiftboundFont.heading)
                        .foregroundStyle(RiftboundPalette.regularText)
                    Text(descriptionText)
                        .font(RiftboundFont.body)
                        .italic()
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("\(printing.set.label) · #\(printing.collectorNumber.map(String.init) ?? "?") · \(printing.riftboundID)")
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.45))
            }
            .frame(width: Self.infoColumnWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var artSize: CGSize {
        printing.orientation == .landscape
            ? CGSize(width: 280, height: 200)
            : CGSize(width: 200, height: 280)
    }

    private var abilityText: String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No printed ability." : text
    }

    /// The mockup's "Lorem ipsum" body under the Description header is the
    /// card's flavour text — the one field `InlineCardDetail`'s Type/Cost/
    /// Ability rows don't already cover.
    private var descriptionText: String {
        guard let flavour = printing.text.flavour?.trimmingCharacters(in: .whitespacesAndNewlines),
              !flavour.isEmpty else {
            return "No flavour text."
        }
        return flavour
    }
}
