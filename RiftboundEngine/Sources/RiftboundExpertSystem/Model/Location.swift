/// Rule 106: Locations are Base and Battlefields only. Hand, Trash,
/// Main/Rune Deck, Banishment, Legend Zone, Champion Zone are Zones but
/// NOT Locations (106.5.b, 107.x) — units cannot "move" to/from them via
/// the Standard Move (rule 140.4), only via specific card effects.
public enum Location: Hashable, Codable, Sendable {
    case base(PlayerID)
    case battlefield(BattlefieldID)
}

/// Rule 119–123: a Game Object is anything that can produce Game Effects or
/// act as a prerequisite for Game Actions. This is a strictly larger set
/// than `Card` — Runes, Legends, Battlefields, Tokens, and even in-flight
/// abilities on the Chain all qualify (rule 123).
///
/// Do not conflate this with `Card`. See CLAUDE.md point 1.
public protocol GameObject {
    var id: ObjectID { get }
    var owner: PlayerID { get }
    var controller: PlayerID { get set }
}
