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
/// Every physical region of the table a card can be observed in.
///
/// Rule 106 draws a line this enum deliberately does not: only Base and
/// Battlefield are *Locations*; Hand, Trash, the decks, Banishment, the
/// Legend and Champion zones are Zones but not Locations (106.5.b). That
/// distinction still matters to the rules, and `TableRegion.location`
/// preserves it — but the vision layer has to be able to *say* "this card
/// is in the Trash" before the rules can decide it doesn't matter. Only
/// naming Locations meant six of the mat's regions had no representation
/// at all, so a card entering them was dropped at the boundary and Draw
/// and Channel Rune were unreachable however well tracking worked.
public enum TableZone: Sendable, Equatable, Hashable {
    case hand
    case base
    case battlefield(BattlefieldID)
    case mainDeck
    case runeDeck
    case runeArea
    case trash
    case banishment
    case legendZone
    case championZone
}

public struct TableRegion: Sendable, Equatable {
    public let owner: PlayerID
    public let zone: TableZone

    public init(owner: PlayerID, zone: TableZone) {
        self.owner = owner
        self.zone = zone
    }

    /// Rule 106: Base and Battlefield are the only Locations. Everything
    /// else is a Zone a card can sit in but not a place a Unit can Move to,
    /// so this is `nil` there by design rather than by omission.
    public var location: Location? {
        switch zone {
        case .base: return .base(owner)
        case .battlefield(let battlefieldID): return .battlefield(battlefieldID)
        default: return nil
        }
    }

    public var isHandRegion: Bool {
        if case .hand = zone { return true }
        return false
    }

    /// Convenience for the Location-shaped call sites that predate
    /// `TableZone`, so they read the same as before.
    public init(owner: PlayerID, location: Location?, isHandRegion: Bool) {
        self.owner = owner
        if isHandRegion {
            self.zone = .hand
        } else {
            switch location {
            case .base: self.zone = .base
            case .battlefield(let id): self.zone = .battlefield(id)
            case nil: self.zone = .hand
            }
        }
    }
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
