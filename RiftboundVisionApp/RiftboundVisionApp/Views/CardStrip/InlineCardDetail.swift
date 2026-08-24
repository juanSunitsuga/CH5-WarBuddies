import SwiftUI
import RiftboundVision

/// The attribute list that opens beside a selected card.
///
/// Deliberately *not* `CardDetailView`, which is the Card Library's
/// full-page browse view and repeats the artwork at full size. Here the
/// card itself is already sitting three pixels to the left, so showing it
/// twice wastes the width and makes the pair read as two cards. This is
/// only the words the art can't tell you.
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
        // `CardAttributeRow`'s value text is `fixedSize(vertical: true)`,
        // so a long Ability (spawned-token flavour text runs several
        // sentences) grew straight past `stripCardHeight` and pushed
        // whatever card came after it in the strip out of place instead of
        // stopping at the panel's own edge. Scrolling keeps the panel's
        // footprint fixed regardless of how long the card's text runs.
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                CardAttributeRow(label: "Type", value: printing.classification.type)
                if let cost = printing.costLabel { CardAttributeRow(label: "Cost", value: cost) }
                CardAttributeRow(label: "Ability", value: abilityText)
            }
        }
        .frame(width: RiftboundLayout.stripDetailWidth, alignment: .leading)
        // A fixed `height`, not `maxHeight`: a `ScrollView` sizes to fit
        // its content when only an upper bound is given, so a short
        // Ability ("No ability.") collapsed to a stub while a longer one
        // on the next card over filled the full row — every panel in the
        // strip needs to read as the same shape regardless of how much
        // text is actually in it.
        .frame(height: RiftboundLayout.stripCardHeight, alignment: .top)
    }

    private var abilityText: String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No printed ability." : text
    }
}

/// One "label: value" line in a card's attribute list — Type, Cost,
/// Ability. Shared by `InlineCardDetail` and `CardDetailView` so the two
/// don't carry their own, independently-drifting copy of the same layout.
struct CardAttributeRow: View {
    let label: String
    let value: String

    var body: some View {
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

extension CardPrinting {
    /// Energy and Power read as one cost line, the way the card prints
    /// them — "2" or "2 + 1 Power". A card with neither returns `nil`
    /// rather than an empty row, since a blank value reads as a loading
    /// state. Shared by `InlineCardDetail` and `CardDetailView` so the two
    /// "Cost" rows can't drift into reporting a card's cost two different
    /// ways.
    var costLabel: String? {
        let energy = attributes.energy
        let power = attributes.power ?? 0
        switch (energy, power) {
        case (nil, 0): return nil
        case (let e?, 0): return "\(e)"
        case (nil, let p): return "\(p) Power"
        case (let e?, let p): return "\(e) + \(p) Power"
        }
    }
}
