/// The result of Stage 1 (OCR + mapping): a physical card observed on the
/// table, resolved to a known card definition. This is *identification
/// only* — it says what card is where, not what action happened. That's
/// deliberate: OCR and Object Tracking are separate concerns (a card can be
/// re-identified every frame without that implying a new action each time).
public struct CardIdentification: Sendable {
    public let cardDefinitionID: CardDefID
    public let physicalRegion: TableRegion
    /// OCR confidence, 0...1. The Ingestion layer (not this type) decides
    /// what confidence threshold is acceptable before treating an
    /// identification as ground truth vs. flagging for confirmation.
    public let confidence: Double

    public init(cardDefinitionID: CardDefID, physicalRegion: TableRegion, confidence: Double) {
        self.cardDefinitionID = cardDefinitionID
        self.physicalRegion = physicalRegion
        self.confidence = confidence
    }
}

/// Where on the physical table something was observed. Deliberately opaque
/// to the engine beyond identifying which player's space and which logical
/// Location it corresponds to — pixel coordinates etc. belong to the
/// vision layer, not here. The Ingestion layer is responsible for mapping
/// raw camera coordinates to one of these before anything reaches the
/// engine; the engine should never see a coordinate.
public struct TableRegion: Sendable, Equatable {
    public let owner: PlayerID
    public let location: Location?   // nil if not yet resolved to a base/battlefield (e.g. still in hand)
    public let isHandRegion: Bool
    /// Which non-Location zone this is, for zones rule 106.5.b excludes
    /// from `Location` (Rune Area, Rune Deck, Main Deck, Trash, Legend,
    /// Champion) — `nil` for Base/Battlefield (covered by `location`) and
    /// Hand (covered by `isHandRegion`). Only `.runeArea`/`.runeDeck` are
    /// actually produced anywhere yet (Channel/Recycle Rune); the others
    /// are declared so the enum doesn't need to grow again for the next
    /// one, but callers must still treat unproduced cases as unreachable.
    public let nonLocationZone: NonLocationZone?

    public init(owner: PlayerID, location: Location?, isHandRegion: Bool, nonLocationZone: NonLocationZone? = nil) {
        self.owner = owner
        self.location = location
        self.isHandRegion = isHandRegion
        self.nonLocationZone = nonLocationZone
    }
}

/// See `TableRegion.nonLocationZone`.
public enum NonLocationZone: Sendable, Equatable {
    case runeArea
    case runeDeck
    case mainDeck
    case trash
    case legend
    case champion
}

/// Whether hands are played face-up (visible to OCR and, physically, to
/// the opponent) or face-down (the rulebook default, rule 107.6.c). This is
/// a deliberate mode choice for a camera-driven physical implementation,
/// not a relaxation the engine should apply silently — plumb it through
/// explicitly so it's visible in game setup/config, and so any future
/// "hidden hand" mode (e.g. player-held device showing only their own hand)
/// doesn't require re-deriving this decision.
public enum InformationMode: Sendable, Equatable {
    /// Rule 107.6.c default: hands are Private Information. Requires a
    /// non-table-camera source of hand contents (e.g. per-player device),
    /// since a table camera physically cannot see face-down cards.
    case standardPrivateHands
    /// House-rule mode: all hands played face-up. Card recognition for
    /// hand cards works the same as for board cards; the engine still
    /// *tracks* privacy per rule 127 internally (in case of a future mixed
    /// mode), but validation does not treat hand contents as unknown to
    /// either player.
    case openHands
}
