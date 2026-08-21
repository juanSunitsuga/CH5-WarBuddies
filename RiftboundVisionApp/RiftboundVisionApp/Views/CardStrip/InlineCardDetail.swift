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
    /// The cost as the two things the player physically does.
    ///
    /// "2 + 1 Power" is how the card prints it, and it tells someone who
    /// doesn't already know the game nothing about what to do. Energy is
    /// paid by *exhausting* runes (157.2.a); Power by *recycling* them to
    /// the bottom of the rune deck (157.2.b/594.1.b) — and Power is usually
    /// domain-locked (130.3), so which rune matters. The panel is narrow,
    /// so this stays terse: the full sentence, with the destination spelled
    /// out, is what the mascot band says while the play is being paid for.
    private var costText: String? {
        let energy = printing.attributes.energy ?? 0
        let power = printing.attributes.power ?? 0
        guard energy > 0 || power > 0 else { return nil }

        var parts: [String] = []
        if energy > 0 {
            parts.append("exhaust \(energy) rune\(energy == 1 ? "" : "s")")
        }
        if power > 0 {
            let named = printing.classification.domain
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " or ")
            parts.append("recycle \(power) \(named.isEmpty ? "" : named + " ")rune\(power == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
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
