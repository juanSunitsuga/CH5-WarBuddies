import Foundation

/// Rule 533–534: a card being played or an ability being activated, sitting
/// on the Chain awaiting resolution. Exactly one `Chain` exists at a time
/// (534.1); new items are always added to the existing one if present
/// (534.2), never spawn a second Chain.
public enum ChainItem: Sendable, Identifiable {
    case spell(MainDeckCard, targets: [ObjectID])
    /// An Activated Ability has no associated card once on the Chain (577.3.a.1) —
    /// only its source object and the effect to execute.
    case activatedAbility(source: ObjectID, effectID: EffectID, targets: [ObjectID])
    /// A Triggered Ability, added when its condition is met (583.3).
    case triggeredAbility(source: ObjectID, effectID: EffectID, targets: [ObjectID])

    public var id: EffectID {
        switch self {
        case .spell(let card, _): return EffectID(rawValue: card.id.rawValue)
        case .activatedAbility(_, let effectID, _): return effectID
        case .triggeredAbility(_, let effectID, _): return effectID
        }
    }
}

/// Identifies a single instance of an ability/effect resolution, distinct
/// from the object that produced it (a unit can have multiple triggered
/// abilities queued at once, per rule 583.3.b).
public struct EffectID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Rule 532–544: the Chain is modeled as a literal stack. `items.last` is
/// always the next thing to resolve (543.1: "the last spell or ability
/// added to the Chain").
///
/// Resolution protocol (do not simplify):
///   1. Determine/re-determine Relevant Players (539, rule 528–531).
///   2. The Active Player may add to the Chain, activate an ability, invite
///      another player, or Pass (540).
///   3. Track passes in `passedPlayers`; once every Relevant Player has
///      passed in sequence without an intervening action, the Chain resolves
///      its top item (540.4.b, 543).
///   4. After an item resolves, run Cleanup (543.3), then re-derive Relevant
///      Players and require a fresh full pass-around for the *new* top item
///      (543.4) — passes do not carry over between items.
///
/// This type intentionally holds no resolution *logic* — see
/// `ChainResolver` for the state-transition functions. Keeping the data
/// structure and the transition logic separate makes the transition logic
/// unit-testable against constructed Chain states without needing a full
/// GameState.
public struct Chain: Sendable {
    // `internal(set)`, not `private(set)`: mutation is meant to happen
    // exclusively through `ChainResolver` (a sibling file in this same
    // module, per this type's own doc comment above), not from outside
    // the module (RiftboundVision/RiftboundTextProcessing/the app, which
    // only ever see `RiftboundExpertSystem`'s public surface). `private`
    // would block same-module-different-file access too, which is
    // exactly the access `ChainResolver` needs.
    public internal(set) var items: [ChainItem]
    public internal(set) var activePlayer: PlayerID
    /// Rule 528–531: who may currently act on this Chain. Re-derived, not
    /// just accumulated — a player who becomes irrelevant should be
    /// removed unless a broader Showdown scope keeps them relevant (530.1).
    public internal(set) var relevantPlayers: Set<PlayerID>
    /// Players who have passed *since the last item was added or resolved*.
    /// Reset whenever `items` changes (540.4.b, 543.4).
    public internal(set) var passedPlayers: Set<PlayerID>

    public init(firstItem: ChainItem, activePlayer: PlayerID, relevantPlayers: Set<PlayerID>) {
        self.items = [firstItem]
        self.activePlayer = activePlayer
        self.relevantPlayers = relevantPlayers
        self.passedPlayers = []
    }
}
