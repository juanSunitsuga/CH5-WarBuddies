/// Rule 545–553: a Window of Opportunity distinct from the Chain. Can be
/// combat-triggered (516.4.f — Combat *includes* a Showdown as a sub-phase)
/// or standalone (516.5.b — moving into an empty contested Battlefield).
///
/// Do not conflate Showdown with Combat: every Combat has a Showdown, but
/// not every Showdown involves a Combat (550.2 — if not part of Combat,
/// *all* players are Relevant, not just two).
public struct Showdown: Sendable {
    public enum Origin: Sendable, Equatable {
        case combat(attacker: PlayerID, defender: PlayerID, battlefield: BattlefieldID)
        case standalone(battlefield: BattlefieldID)
    }

    public let origin: Origin
    /// Rule 549: the player who applied Contested status gains Focus first.
    public private(set) var focusPlayer: PlayerID
    /// Rule 550: initial Relevant Players depend on origin (two, for combat;
    /// all players, for standalone). Can grow via invitation (531.2).
    public private(set) var relevantPlayers: Set<PlayerID>
    /// Rule 553.4.a: tracks passes *at the Showdown level*, separate from
    /// any Chain currently nested inside it.
    public private(set) var passedPlayers: Set<PlayerID>
    /// Rule 551.1: Showdowns from Combat may open with an Initial Chain of
    /// "When I attack"/"When I defend" triggers. nil if none triggered
    /// (551.1.b) or if this is a standalone Showdown.
    public var nestedChain: Chain?

    public init(
        origin: Origin,
        focusPlayer: PlayerID,
        relevantPlayers: Set<PlayerID>,
        nestedChain: Chain? = nil
    ) {
        self.origin = origin
        self.focusPlayer = focusPlayer
        self.relevantPlayers = relevantPlayers
        self.passedPlayers = []
        self.nestedChain = nestedChain
    }

    /// Rule 553.5/552: hand Focus to the next Relevant Player in Turn
    /// Order. Used both when the player with Focus passes (553.5) and when
    /// the last item on a nested Chain resolves (552).
    ///
    /// Wraps around `turnOrder`, skipping non-Relevant players — a Showdown
    /// from Combat has only two Relevant Players (550.1) even at a table of
    /// four, so "the next player" means the next *Relevant* one, not simply
    /// the next seat.
    mutating func passFocus(turnOrder: [PlayerID]) {
        guard let currentIndex = turnOrder.firstIndex(of: focusPlayer), !relevantPlayers.isEmpty else { return }
        for step in 1...turnOrder.count {
            let candidate = turnOrder[(currentIndex + step) % turnOrder.count]
            if relevantPlayers.contains(candidate) {
                focusPlayer = candidate
                return
            }
        }
    }

    /// Rule 553.4: record a Pass at the Showdown level (distinct from
    /// passes on a nested Chain, which `Chain.passedPlayers` tracks).
    mutating func recordPass(by player: PlayerID) {
        passedPlayers.insert(player)
    }

    /// Rule 553.4.a: the Showdown ends once all Relevant Players have
    /// passed once in sequence.
    var allRelevantPlayersPassed: Bool {
        relevantPlayers.isSubset(of: passedPlayers)
    }

    /// Rule 552: a resolving Chain item is something happening, so the
    /// sequence of passes that would have ended the Showdown is broken —
    /// Focus moves on and everyone gets another look.
    mutating func clearPasses() {
        passedPlayers = []
    }
}

/// Rule 624–628: the fixed sequence within a Combat (itself entered via
/// `Showdown.Origin.combat`). Distinct from `Phase` — this only exists
/// while a specific Battlefield's combat is being resolved.
public enum CombatStep: Sendable, Equatable {
    case showdown       // 625: establish Attacker/Defender, apply Assault/Shield, open Initial Chain
    case combatDamage    // 626: sum Might, assign damage (Tank-first, lethal-before-spread)
    case resolution       // 627: remove lethal-damaged units, recall survivors, conquer if applicable
}
