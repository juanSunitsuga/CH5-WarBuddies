import CoreGraphics

/// Which physical seat an object/zone belongs to. Deliberately NOT the
/// Expert System's `PlayerID` (an opaque UUID minted when `GameState` is
/// constructed) — this is a physical-table concept ("the person sitting on
/// the left"). `ExpertSystemAdapter` owns the calibration mapping from
/// `Player` to `PlayerID`, established once at game setup, the same way it
/// maps `TrackedObjectID` to card identity.
public enum Player: Sendable, Equatable, Codable {
    case player1
    case player2
    // TODO: 3+ player modes (Skirmish/War, rules 646–647) need more seats.
}

/// A coarse, geometrically-calibrated tabletop region. Kept flat rather
/// than modeling every possible Battlefield separately, per the brief:
/// "preferably calibrated polygons/rectangles rather than repeatedly
/// detected by ML."
public enum Zone: String, Sendable, Equatable, Codable, CaseIterable {
    case player1Hand
    case player2Hand
    case mainDeck
    case runeDeck
    case trash
    case base
    case battlefield
    case runeArea
    /// The printed "Legend" box on the playmat (rule 107.2/162 —
    /// `ChampionLegend`'s home zone).
    case legend
    /// The printed "Champion" box on the playmat — where the Chosen
    /// Champion card sits before being played (`PlayerZones.championZoneCard`).
    case champion
    case unknown

    /// Convenience derivation for the player-specific cases. `nil` for
    /// zones that aren't inherently tied to one seat (`battlefield`,
    /// `runeArea` may host either/both players' objects; disambiguating
    /// *which* Base/Battlefield/Rune Area a given `BoardZone` instance
    /// belongs to is `BoardZone.owner`'s job, not this enum's).
    public var impliedOwner: Player? {
        switch self {
        case .player1Hand: return .player1
        case .player2Hand: return .player2
        default: return nil
        }
    }

    /// A card that's reached Battlefield, Rune Area, or Rune Deck doesn't
    /// move under normal play — a Unit stays on its Battlefield until it
    /// leaves play entirely (kill/banish/recycle, not a same-zone shuffle),
    /// and Runes sit in the Rune Deck or Rune Area only ever rotating in
    /// place (Exhaust/Ready). `CameraPipelineController` uses this to
    /// relax how hard it works re-confirming these objects are still
    /// there — see its detection-cadence throttle and
    /// `ObjectTracker.settledOcclusionToleranceFrames`. Hand, in-transit,
    /// and deck/trash piles are excluded on purpose: those are exactly the
    /// zones where a card's presence *can* change from one frame to the
    /// next and needs to be re-detected promptly.
    public var isPositionallyStable: Bool {
        switch self {
        case .battlefield, .runeArea, .runeDeck: return true
        default: return false
        }
    }
}

/// One physically-calibrated region on the table — e.g. "Player 1's Hand"
/// is a specific quadrilateral in camera-space, calibrated once (not
/// re-detected by ML every frame).
public struct BoardZone: Sendable {
    public let type: Zone
    public let polygon: [CGPoint]
    /// Which seat this specific calibrated instance belongs to, for zones
    /// that exist once per player (Base, Main Deck, Rune Deck, Trash, Rune
    /// Area). `Zone.impliedOwner` covers Hand automatically; set this
    /// explicitly for the others since one `Zone` case may have multiple
    /// physical, per-player instances.
    public let owner: Player?
    /// Which physical Battlefield card this calibrated region corresponds
    /// to, for `.battlefield` zones on boards with more than one
    /// Battlefield in play (a real Riftbound game can have several).
    /// `ExpertSystemAdapter` still has to resolve this slot number to the
    /// actual `BattlefieldID` the Expert System assigned at game setup —
    /// that mapping is calibration data this type doesn't own.
    public let battlefieldSlot: Int?

    public init(type: Zone, polygon: [CGPoint], owner: Player? = nil, battlefieldSlot: Int? = nil) {
        self.type = type
        self.polygon = polygon
        self.owner = owner ?? type.impliedOwner
        self.battlefieldSlot = battlefieldSlot
    }

    /// Standard ray-casting point-in-polygon test. `polygon` must have at
    /// least 3 points; zones with fewer are treated as never containing
    /// anything (calibration bug, not a runtime crash).
    public func contains(_ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let slopeX = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < slopeX {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }
}

/// Resolves a raw camera-space point to a calibrated `Zone`, and — for
/// zones that need it — the specific `BoardZone` instance (to recover
/// `owner`/`battlefieldSlot`). Calibration (the actual polygons) is
/// supplied by the caller, not hardcoded here — that data comes from a
/// one-time setup step against the physical table, not from ML detection.
public struct ZoneMapper: Sendable {
    public let zones: [BoardZone]

    public init(zones: [BoardZone]) {
        self.zones = zones
    }

    /// First matching calibrated zone, or `.unknown` if the point falls
    /// outside every calibrated region (e.g. a card mid-transit between
    /// zones, or off the play area entirely).
    public func zone(for point: CGPoint) -> Zone {
        boardZone(for: point)?.type ?? .unknown
    }

    public func boardZone(for point: CGPoint) -> BoardZone? {
        zones.first { $0.contains(point) }
    }
}
