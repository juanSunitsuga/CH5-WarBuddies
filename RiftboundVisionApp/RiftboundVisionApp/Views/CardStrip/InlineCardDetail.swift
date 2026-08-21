import SwiftUI
import RiftboundVision
import RiftboundTextProcessing

/// The attribute list that opens beside a selected card.
///
/// Deliberately *not* `CardDetailView`. That one repeats the artwork and
/// carries a Close button, which made sense in a sidebar where it was the
/// only thing on screen. Here the card itself is already sitting three
/// pixels to the left, so showing it twice wastes the width and makes the
/// pair read as two cards. This is only the words the art can't tell you.
struct InlineCardDetail: View {
    let printing: CardPrinting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Type", printing.classification.type)
            if let cost = costText { row("Cost", cost) }
            row("Ability", abilityText)
        }
        .frame(width: RiftboundLayout.stripDetailWidth, alignment: .leading)
        .frame(maxHeight: RiftboundLayout.stripCardHeight, alignment: .top)
    }

    /// Energy and Power read as one cost line, the way the card prints
    /// them — "2" or "2 + 1 Power". A card with neither says so rather than
    /// showing an empty row, since a blank value reads as a loading state.
    private var costText: String? {
        let energy = printing.attributes.energy
        let power = printing.attributes.power ?? 0
        switch (energy, power) {
        case (nil, 0): return nil
        case (let e?, 0): return "\(e)"
        case (nil, let p): return "\(p) Power"
        case (let e?, let p): return "\(e) + \(p) Power"
        }
    }

    /// The card's ability in plain words, not as printed.
    ///
    /// Printed text is written for someone who already speaks the game —
    /// `[Tank]`, `:rb_might:`, "recycle it" — and this panel is exactly
    /// where a player goes when they *don't* know what a card does. So it
    /// shows `CardPlainLanguage`'s rendering: keywords spelled out, icon
    /// markup turned into words, and each triggered ability split into its
    /// condition and its effect.
    ///
    /// A keyword the rulebook glossary doesn't cover is appended as printed
    /// rather than paraphrased — see `Explanation.unexplained`. Showing it
    /// raw is honest; inventing a meaning would be a rule the player can't
    /// check.
    private var abilityText: String {
        let explanation = CardPlainLanguage.explain(printing.text.plain)
        var lines = explanation.lines
        lines.append(contentsOf: explanation.unexplained)
        guard !lines.isEmpty else { return "No printed ability." }
        return lines.joined(separator: "\n")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(RiftboundFont.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
