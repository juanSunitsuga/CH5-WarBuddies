/// Rule 179–181: Control is tracked per-Battlefield, separately from any
/// single Unit's `controller` field, because a Battlefield can be
/// Controlled/Uncontrolled/Contested as its own state (181.2–181.3).
public struct BattlefieldControl: Sendable, Equatable {
    public var controller: PlayerID?          // nil = Uncontrolled (181.2.b)
    public var isContested: Bool = false       // 181.3 — temporary status
    /// Rule 181.3.a / 549: the player whose Unit's Move most recently
    /// applied Contested status — this is who gains Focus (549) or becomes
    /// Attacker (625.1.a.1) when a Showdown opens here. Cleared whenever
    /// `isContested` is cleared (Control is (re-)established, 181.3.b).
    public var contestedBy: PlayerID?
    /// Rule 524/524.1: set while Units controlled by two opposing players
    /// are simultaneously present at this Battlefield; cleared as soon as
    /// that stops being true. Recomputed by `Cleanup` each pass — not
    /// mutated directly by action application.
    public var combatPending: Bool = false
    /// Players who have already Scored this Battlefield *this turn*
    /// (rule 631: once per Battlefield per turn, by either method).
    public var scoredThisTurnBy: Set<PlayerID> = []

    public init(
        controller: PlayerID? = nil,
        isContested: Bool = false,
        contestedBy: PlayerID? = nil,
        combatPending: Bool = false,
        scoredThisTurnBy: Set<PlayerID> = []
    ) {
        self.controller = controller
        self.isContested = isContested
        self.contestedBy = contestedBy
        self.combatPending = combatPending
        self.scoredThisTurnBy = scoredThisTurnBy
    }
}

/// The full, single-source-of-truth snapshot of a game in progress.
///
/// This is a plain `Sendable` value type on purpose — see `GameStateStore`
/// for the actor that owns and serializes mutation of it. Keeping this a
/// value type (rather than a class/actor itself) makes Cleanup, Layers, and
/// effect resolution pure functions of the form `(GameState) -> GameState`,
/// which is what makes them independently unit-testable and makes
/// state-snapshot/undo/replay close to free.
public struct GameState: Sendable {
    public var turnOrder: [PlayerID]           // rule 115.1: repeating sequence
    public var turnPlayerIndex: Int
    public var turnState: TurnState = .neutralOpen
    public var phase: Phase = .startOfTurn(.awaken)

    public var units: [ObjectID: Unit] = [:]
    public var gear: [ObjectID: Gear] = [:]
    /// Rule 154/606.1: Runes that have been Channeled onto the board and
    /// now sit in their controller's Rune Area. Keyed the same way as
    /// `units` rather than grouped per player — a Rune knows its own
    /// controller, and one flat table means "every Rune in the game" is a
    /// single lookup for Awaken (515.1) and the vision layer's rune count.
    public var runes: [ObjectID: Rune] = [:]
    public var battlefields: [BattlefieldID: Battlefield]
    public var battlefieldControl: [BattlefieldID: BattlefieldControl] = [:]
    /// Rule 106.4: at most one card per Battlefield's Facedown Zone.
    public var facedownZones: [BattlefieldID: (owner: PlayerID, card: MainDeckCard)] = [:]

    public var zones: [PlayerID: PlayerZones]
    public var scores: [PlayerID: Int]

    /// Rule 154.3: cumulative Runes ever Channeled by each player, across
    /// the whole game — unlike `RunePool.energy`, this never empties
    /// (515.4.d/160/517.2.c), so it's the right quantity for a pace check
    /// ("2 Runes/turn, so 6 by turn 3"), not the pool itself. Populated by
    /// `GameActionApplier`'s `.channel` handling.
    public var totalRunesChanneled: [PlayerID: Int] = [:]
    /// Rule 130.3: cumulative Runes ever Recycled to pay a Power cost.
    /// `totalRunesChanneled - totalRunesRecycled` is the count of Runes
    /// that should still physically be visible in a player's Rune Area —
    /// the quantity to reconcile against the vision layer's live count,
    /// not `totalRunesChanneled` alone (recycling removes a Rune from view
    /// without un-channeling it historically).
    public var totalRunesRecycled: [PlayerID: Int] = [:]

    /// How many of their own turns each player has completed the Channel
    /// Step of. Rule 646.6/647.7: the player going second Channels 3 on
    /// their first turn instead of 2, so the Channel Step has to know which
    /// turn this is for *this* player — a global turn counter can't answer
    /// that. Read by `RuneChannelPace.runesToChannel(for:turnOrder:completedTurns:)`.
    public var completedChannelSteps: [PlayerID: Int] = [:]

    /// Rule 633: points needed to win, per the Mode of Play. 8 for the
    /// standard 1v1 mode (645.5); carried on the state rather than hardcoded
    /// in `Scoring` so team/multiplayer modes (646–648) can set their own
    /// without the scoring rules needing to know which mode they're in.
    public var victoryScore: Int = 8

    /// Rule 633: set the moment a player reaches `victoryScore`. Nothing
    /// beyond this point should be applied — the game ended immediately
    /// ("they Win the Game immediately"), so this is checked rather than
    /// inferred from `scores` by every caller in turn.
    public var winner: PlayerID?

    /// Rule 589.2: a Limited Action "is only ever performed when a rule or
    /// effect explicitly calls for it" — never chosen freely by a player.
    /// This is that authorization ledger: a Chain item resolving to, say,
    /// `EffectInstruction.draw(count: 1)` appends `.draw(count: 1)` here for
    /// the relevant player via `authorize(_:for:)` *before* anything on the
    /// physical table is allowed to reflect it. `LegalityValidator` checks
    /// membership here for every Limited Action case; `GameActionApplier`
    /// consumes (removes) the matching entry once applied.
    ///
    /// This exists precisely to catch the "player drew before their card's
    /// enter-play trigger actually resolved" case: OCR/tracking proposes
    /// `.draw(count: 1)` same as always, but nothing has called `authorize`
    /// for it yet, so the Validator rejects it and `GameState` never
    /// reflects the physical draw — the player has to put the card back,
    /// not the engine.
    public var pendingLimitedActions: [PlayerID: [GameAction]] = [:]

    public var turnPlayer: PlayerID { turnOrder[turnPlayerIndex] }

    /// Rule 589.2 — the hook effect execution (a resolving Chain item, or a
    /// fixed turn-structure point like the Draw Phase) calls to grant a
    /// player permission to perform one specific Limited Action. Until the
    /// Chain/Effect-resolution pipeline exists, callers (including tests)
    /// invoke this directly to simulate "an ability just resolved and now
    /// calls for this."
    public mutating func authorize(_ action: GameAction, for player: PlayerID) {
        pendingLimitedActions[player, default: []].append(action)
    }

    public init(
        turnOrder: [PlayerID],
        battlefields: [BattlefieldID: Battlefield],
        zones: [PlayerID: PlayerZones]
    ) {
        precondition(!turnOrder.isEmpty, "turnOrder must have at least one player")
        self.turnOrder = turnOrder
        self.turnPlayerIndex = 0
        self.battlefields = battlefields
        self.zones = zones
        self.scores = Dictionary(uniqueKeysWithValues: turnOrder.map { ($0, 0) })
        self.battlefieldControl = Dictionary(
            uniqueKeysWithValues: battlefields.keys.map { ($0, BattlefieldControl()) }
        )
    }
}
