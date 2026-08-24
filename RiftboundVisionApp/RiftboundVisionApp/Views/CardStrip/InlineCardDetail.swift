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
            VStack(alignment: .leading, spacing: 8) {
                CardAttributeRow(label: "Type", value: printing.classification.type)
                if let cost = printing.costLabel { CardAttributeRow(label: "Cost", value: cost) }
                CardAttributeRow(label: "Ability") {
                    CardAbilityValue(keywords: printing.printedKeywords, text: abilityText)
                }
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
///
/// Generic over its value so the Ability line can hand in keyword chips
/// plus text where Type and Cost hand in a plain string. The alternative
/// — a second row type just for Ability — is how the label column would
/// end up two different widths in the two places this is drawn.
struct CardAttributeRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
                .frame(width: RiftboundLayout.cardAttributeLabelWidth, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension CardAttributeRow where Value == CardAttributeText {
    /// The plain-string case — Type and Cost. Keeps every existing call
    /// site reading exactly as it did before the row went generic.
    init(label: String, value: String) {
        self.init(label: label) { CardAttributeText(value) }
    }
}

/// A value's default styling. A named view rather than modifiers repeated
/// at each call site, so the Ability line's body text and the Type/Cost
/// values can't end up at different weights or opacities.
struct CardAttributeText: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RiftboundFont.body)
            .foregroundStyle(RiftboundPalette.regularText.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Ability line: printed keywords as gold pills, then the readable
/// text beneath them.
///
/// The two come from *different* sources and that's the point. Keywords
/// are parsed out of the card's printed text (`[Assault]`), while the
/// sentence under them is the simplified, first-timer-friendly rewrite
/// (`simple_text`) — which deliberately spells the keyword out rather
/// than naming it, so a player who only ever reads the simplified copy
/// would never learn the word the rest of the game uses. Showing the pill
/// alongside is what connects the two.
struct CardAbilityValue: View {
    let keywords: [String]
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !keywords.isEmpty {
                HStack(spacing: 6) {
                    ForEach(keywords, id: \.self) { CardKeywordChip(keyword: $0) }
                }
            }
            CardAttributeText(text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One printed keyword, as the gold box the physical card prints it in.
struct CardKeywordChip: View {
    let keyword: String

    var body: some View {
        Text(keyword.uppercased())
            .font(RiftboundFont.heading)
            // Dark-on-gold, the same inversion the lit phase pip uses —
            // cream text on `highlightOverlay` is the one pairing in this
            // palette that doesn't hold up.
            .foregroundStyle(RiftboundPalette.elementShadow)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: RiftboundLayout.keywordChipCornerRadius, style: .continuous)
                    .fill(RiftboundPalette.highlightOverlay)
            )
    }
}

extension CardPrinting {
    /// The keywords this card prints in brackets — `[Assault]`,
    /// `[Deflect 2]` — in the order they appear, without their brackets
    /// or reminder text.
    ///
    /// Read from `text.plain` specifically, *not* from the simplified
    /// copy the panel shows as body text: the simplification's whole job
    /// is to replace "Assault" with what Assault does, so it is by
    /// construction the one string that has already thrown this away.
    ///
    /// The leading `[A-Za-z]` requirement is load-bearing — printed text
    /// also uses brackets for costs (`[1]`, `[2]`), and those are not
    /// keywords. A trailing number *is* kept out of the pill's name so
    /// `[Deflect 2]` chips as "DEFLECT"; the value is in the rules text
    /// underneath either way.
    var printedKeywords: [String] {
        let source = text.plain
        guard let regex = try? NSRegularExpression(pattern: #"\[([A-Za-z][A-Za-z' ]*?)(?:\s+\d+)?\]"#) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        var seen = Set<String>()
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: source) else { return nil }
            let keyword = source[captured].trimmingCharacters(in: .whitespaces)
            // Deduplicated: a card that both grants and has a keyword
            // prints it twice, and two identical pills read as a bug.
            guard !keyword.isEmpty, seen.insert(keyword.lowercased()).inserted else { return nil }
            return keyword
        }
    }

    /// The cost as the two things the player physically does.
    ///
    /// "2 + 1 Power" is how the card prints it, and it tells someone who
    /// doesn't already know the game nothing about what to do. Energy is
    /// paid by *exhausting* runes (157.2.a); Power by *recycling* them to
    /// the bottom of the rune deck (157.2.b/594.1.b) — and Power is usually
    /// domain-locked (130.3), so which rune matters. The panels are narrow,
    /// so this stays terse: the full sentence, with the destination spelled
    /// out, is what the mascot band says while the play is being paid for.
    ///
    /// A card with neither returns `nil` rather than an empty row, since a
    /// blank value reads as a loading state. Lives on `CardPrinting` so
    /// `InlineCardDetail` and `CardDetailView` can't drift into reporting a
    /// card's cost two different ways.
    var costLabel: String? {
        let energy = attributes.energy ?? 0
        let power = attributes.power ?? 0
        guard energy > 0 || power > 0 else { return nil }

        var parts: [String] = []
        if energy > 0 {
            parts.append("exhaust \(energy) rune\(energy == 1 ? "" : "s")")
        }
        if power > 0 {
            let named = classification.domain
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " or ")
            parts.append("recycle \(power) \(named.isEmpty ? "" : named + " ")rune\(power == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}
