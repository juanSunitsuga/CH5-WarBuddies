import SwiftUI
import RiftboundVision

/// The attribute list that opens beside a selected card.
///
/// Deliberately *not* `CardDetailView`. That one repeats the artwork and
/// carries a Close button, which made sense in a sidebar where it was the
/// only thing on screen. Here the card itself is already sitting three
/// pixels to the left, so showing it twice wastes the width and makes the
/// pair read as two cards. This is only the words the art can't tell you.
struct InlineCardDetail: View {
    let printing: CardPrinting
    /// Rules text for `printing`, resolved by the caller (see
    /// `CameraPipelineController.description(for:)`) — a simplified,
    /// first-timer-friendly rewrite where the card database has one,
    /// falling back through its tag-resolved copy to the raw printed text.
    /// Passed in rather than read from `printing.text.plain` directly so
    /// this view doesn't need its own `CameraPipelineController` reference
    /// just to ask one question.
    let description: String

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

    private var abilityText: String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No printed ability." : text
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
