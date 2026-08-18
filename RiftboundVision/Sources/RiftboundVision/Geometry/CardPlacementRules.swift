import Foundation

/// The categories of card this layer distinguishes for placement purposes.
///
/// Coarser than `RiftboundExpertSystem`'s type system on purpose: this is a
/// vision-layer plausibility check, not a rules decision. It answers "could
/// a card of this kind physically be here", which is a useful filter on a
/// detector that occasionally reads one card as another.
public enum CardKind: String, Sendable, Equatable, CaseIterable {
    case unit
    case champion
    case spell
    case rune
    case gear
    case legend
    case battlefield
    case unknown

    /// Maps `CardPrinting.classification.type` onto a kind, using
    /// `supertype` only to tell a Champion Unit from an ordinary one.
    ///
    /// **`type` is authoritative; `supertype` is a tag, not a card type.**
    /// `supertype: "Champion"` is the champion tag (rule 169 / 103.2.a.2 —
    /// what a Legend is matched against to find its Chosen Champion), and
    /// the catalogue puts it on *both* kinds of card that depict a champion:
    ///
    /// | `type` | `supertype` | e.g. |
    /// |---|---|---|
    /// | `Legend` | `Champion` | Annie - Dark Child (Starter) |
    /// | `Unit` | `Champion` | Lux - Illuminated |
    ///
    /// Testing `supertype` first therefore classified **every Legend in
    /// every deck** as a Champion. Champions aren't allowed in the Legend
    /// zone, so the Legend zone was reported misplaced permanently, on a
    /// card sitting exactly where the rules require it (166–169). The
    /// player was told to move the one card they cannot move.
    public static func from(type: String, supertype: String? = nil) -> CardKind {
        switch type.lowercased() {
        case "unit":
            // The only place the champion tag changes the kind: a Champion
            // Unit may also occupy the Champion zone (107.2).
            return supertype?.localizedCaseInsensitiveContains("champion") == true ? .champion : .unit
        case "spell": return .spell
        case "rune": return .rune
        case "gear": return .gear
        case "legend": return .legend
        case "battlefield": return .battlefield
        default: return .unknown
        }
    }
}

/// Which zones each kind of card can physically occupy.
///
/// This is a noise filter, not a rules engine. The detector re-reads every
/// card several times a second and occasionally returns the wrong one; a
/// Rune reported in the Base is far more likely to be a misread than a
/// player breaking the rules. Rejecting placements that can't happen keeps
/// those readings from becoming tracks, events, and eventually wrong game
/// state.
///
/// Deliberately permissive where the physical table is ambiguous: an
/// unrecognized card is allowed anywhere, because refusing to track what we
/// can't name would be worse than tracking it loosely.
public struct CardPlacementRules: Sendable {
    public init() {}

    /// Zones a kind may legitimately occupy.
    ///
    /// Two deviations from a strict reading, both physical rather than
    /// rules-driven:
    ///
    /// - Runes include the Rune Deck. "Runes only live in the Rune Area" is
    ///   true of *played* runes, but the Rune Deck is literally a stack of
    ///   them and would otherwise be flagged on every poll.
    /// - Every kind except Rune includes the Trash. Runes are excluded
    ///   there by the same instruction that put them in the Rune Area.
    public func allowedZones(for kind: CardKind) -> Set<Zone> {
        switch kind {
        case .rune:
            return [.runeArea, .runeDeck]

        case .unit:
            return [.player1Hand, .player2Hand, .base, .battlefield, .mainDeck, .trash]

        case .champion:
            return [.player1Hand, .player2Hand, .base, .battlefield, .champion, .mainDeck, .trash]

        case .spell:
            return [.player1Hand, .player2Hand, .base, .mainDeck, .trash]

        case .gear:
            // Rule 144.2: Gear sits at a Base once played.
            return [.player1Hand, .player2Hand, .base, .mainDeck, .trash]

        case .legend:
            return [.legend]

        case .battlefield:
            return [.battlefield]

        case .unknown:
            // Nothing is known about it, so nothing can be ruled out.
            return Set(Zone.allCases)
        }
    }

    /// Whether a card of `kind` could be in `zone`.
    ///
    /// `.unknown` zones — a card in transit between calibrated regions, or
    /// off the mat — are always allowed: a card being carried isn't in a
    /// wrong place, it's between places.
    public func isPlausible(kind: CardKind, in zone: Zone) -> Bool {
        guard zone != .unknown else { return true }
        return allowedZones(for: kind).contains(zone)
    }
}
