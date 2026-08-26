import SwiftUI
import RiftboundVision

/// A card's details, as a compact popup over the Card Library's own
/// result list — art on the left, the words on the right.
///
/// This used to be a full page that *replaced* the list, with a Back
/// button in the library's header to return. The hi-fi puts it on top
/// instead, and that's the better shape for what it's for: browsing a
/// catalogue is a sequence of "what's this one?" glances, and a view that
/// takes the whole window makes each glance cost a navigation there and
/// back. Floating it keeps the grid you were reading still on screen
/// behind, so closing is a dismissal rather than a return trip.
///
/// Deliberately *not* `InlineCardDetail` — that one sits beside a
/// thumbnail already on screen in the table strip and omits the artwork
/// for exactly that reason. Both share `CardAttributeText`,
/// `CardAbilityValue` and `CardKeywordChip` so a card's Ability can't
/// read differently depending on where you looked it up.
struct CardDetailView: View {
    let printing: CardPrinting
    /// Rules text for `printing`, resolved by the caller (see
    /// `CameraPipelineController.description(for:)`) — the same
    /// simplified, first-timer-friendly text `InlineCardDetail` shows.
    let description: String
    let onClose: () -> Void
    /// Tapping the art asks the *sheet* to show it large, rather than
    /// this view growing in place: at this popup's size there's no room
    /// to read the art at any useful scale, and the enlarged version has
    /// to be free to cover the whole library behind it.
    let onExpandArt: () -> Void
    /// Whether Escape closes the popup. False while the enlarged art is
    /// up — Escape should dismiss that first, and two `.cancelAction`s in
    /// one window fight over which one fires.
    var isEscapeShortcutActive = true

    /// Wide enough for the stat line to stay on one line at the longest
    /// real combination ("Battlefield | COST: 10 | MIGHT: 10") — it reads
    /// as a single printed line on the card, and wrapping it in the
    /// middle turns it back into a list.
    private static let popupWidth: CGFloat = 420

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onExpandArt) {
                CardArtView(printing: printing, cornerRadius: 4, showsFailureLabel: false)
                    .frame(width: artSize.width, height: artSize.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to see the art full size")
            .accessibilityLabel("Enlarge \(printing.name) artwork")

            VStack(alignment: .leading, spacing: 8) {
                Text(printing.name)
                    .riftFont(.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(statLine)
                    .riftFont(.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
                    .fixedSize(horizontal: false, vertical: true)

                // Omitted entirely for a card with nothing to say — see
                // `InlineCardDetail`'s matching comment.
                if !abilityText.isEmpty || !printing.printedKeywords.isEmpty {
                    CardAbilityValue(keywords: printing.printedKeywords, text: abilityText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The extra trailing inset is the gutter the close button floats
        // in, so a long card name wraps clear of it instead of running
        // underneath. It's padding rather than a `Color.clear` spacer in
        // the `HStack`: `Color` is infinitely flexible in *both* axes, so
        // one sized only by width still stretched the row — and with it
        // the whole popup — to the full height of whatever it was placed
        // in, which is where all the empty space came from.
        .padding(20)
        .padding(.trailing, 18)
        .frame(width: Self.popupWidth)
        .background(
            RoundedRectangle(cornerRadius: RiftboundLayout.cornerRadius, style: .continuous)
                .fill(RiftboundPalette.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RiftboundLayout.cornerRadius, style: .continuous)
                .stroke(RiftboundPalette.elementStroke, lineWidth: RiftboundLayout.hairline)
        )
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .riftIcon(size: 13, weight: .bold)
                .foregroundStyle(RiftboundPalette.regularText)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isEscapeShortcutActive ? .cancelAction : nil)
        .accessibilityLabel("Close card details")
    }

    /// Battlefields print *landscape* — `CardOrientation`'s own doc
    /// comment notes it as the one exception to every other type being
    /// portrait. A fixed portrait frame around one just left the art
    /// letterboxed inside a too-tall box.
    private var artSize: CGSize {
        printing.orientation == .landscape
            ? CGSize(width: 126, height: 90)
            : CGSize(width: 108, height: 151)
    }

    /// "Unit | COST: 2 | MIGHT: 2", the hi-fi's one-line summary.
    ///
    /// Built by dropping the parts a card doesn't have rather than
    /// printing them empty or zero: a Rune has no cost and no Might, and
    /// "Rune | COST: — | MIGHT: —" states two absences where the card
    /// itself simply says nothing.
    private var statLine: String {
        var parts = [printing.classification.type]
        if let energy = printing.attributes.energy { parts.append("COST: \(energy)") }
        if let might = printing.attributes.might { parts.append("MIGHT: \(might)") }
        return parts.joined(separator: " | ")
    }

    private var abilityText: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
