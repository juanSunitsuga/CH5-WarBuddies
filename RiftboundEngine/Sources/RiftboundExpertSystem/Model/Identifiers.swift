import Foundation

/// Identifies a player in the game. Stable for the lifetime of a match.
public struct PlayerID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Identifies a single instance of a Game Object on the board (rule 119–123).
/// Two copies of the same named card are different `ObjectID`s.
public struct ObjectID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Identifies a card *definition* (its printed text/stats), as distinct from
/// any particular physical/in-game instance of it. Used to look up parsed
/// ability text from the NLP layer. Corresponds to a printed card's unique
/// name (rule 131).
public struct CardDefID: Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies a specific Battlefield card in play (rule 162–165).
public struct BattlefieldID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
