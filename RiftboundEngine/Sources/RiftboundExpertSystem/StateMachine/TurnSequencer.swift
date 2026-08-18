/// Rule 514–517: drives the parts of the turn that are **not** the player's
/// to choose.
///
/// The shape of a Riftbound turn is one fixed prefix and then nothing:
///
///     Awaken → Beginning → Channel → Draw  │  Action Phase  │  End of Turn
///     ├──────── fixed, automatic ─────────┤  └ free-form ┘   └ automatic ┘
///
/// Everything before the Action Phase happens in a fixed order with no
/// player input (515), and everything after it is bookkeeping (517). The
/// Action Phase itself "has no defined structure" (516.2) — a player may
/// move units, play cards, and trigger Showdowns in any order and any
/// number of times until they choose to end the turn (516.6). There is no
/// Action → Showdown → End sequence inside it, and no engine-imposed order
/// of any kind; a Showdown is something a Move *causes* (516.5.b), not a
/// step the turn advances into.
///
/// So this type advances the fixed parts and then stops. `.action` is
/// terminal here — only `GameAction.endTurn` leaves it (516.6), which is
/// why `advance` refuses to move past it while `endTurn` is a separate
/// entry point.
///
/// Pure `(GameState) -> GameState`, same as `Cleanup.run`, so the whole
/// turn structure is testable without a live pipeline. Callers run these
/// only through `GameStateStore.mutate` (CLAUDE.md point 2).
public enum TurnSequencer {
    /// Performs the current phase's automatic work and moves to the next
    /// phase. Repeated calls walk Awaken → Beginning → Channel → Draw →
    /// Action and then stop.
    ///
    /// Returns the state unchanged once the Action Phase is reached: what
    /// happens there is the player's business (516.2), and once the game
    /// has been won (633) nothing further is applied at all.
    public static func advance(_ state: GameState) -> GameState {
        advanceReporting(state).state
    }

    /// What advancing produced. Scoring is the only phase work that has
    /// something to tell the player (the Beginning Phase's Holds, 630.2),
    /// and a Hold can win the game (633) — neither is derivable from the
    /// returned `GameState` alone without diffing it, so they're returned.
    public struct Outcome: Sendable {
        public var state: GameState
        public var events: [PlayerInstruction]
    }

    /// `advance` with the player-facing events retained.
    public static func advanceReporting(_ state: GameState) -> Outcome {
        guard state.winner == nil else { return Outcome(state: state, events: []) }
        var state = state
        var events: [PlayerInstruction] = []

        switch state.phase {
        case .startOfTurn(.awaken):
            awaken(&state)                              // 515.1
            state.phase = .startOfTurn(.beginning)

        case .startOfTurn(.beginning):
            let scored = Scoring.scoreHoldsReporting(state)   // 515.2.b.1 / 630.2
            state = scored.state
            events += scored.events
            state.phase = .startOfTurn(.channel)

        case .startOfTurn(.channel):
            channel(&state)                             // 515.3
            state.phase = .startOfTurn(.draw)

        case .startOfTurn(.draw):
            drawStep(&state)                            // 515.4
            state.phase = .action                       // 516.1

        case .action:
            break                                       // 516.2: the player's, not ours

        case .endOfTurn:
            state = endTurn(state)
        }

        return Outcome(state: state, events: events)
    }

    /// Runs the whole fixed prefix in one call: Awaken through Draw,
    /// stopping at the Action Phase. Convenience for callers that want the
    /// turn *started* rather than stepped one phase at a time — the phases
    /// have no windows of opportunity between them for anyone to act in
    /// (515 grants none), so running them individually is only useful for
    /// tests asserting a specific step's effect.
    public static func startTurn(_ state: GameState) -> GameState {
        startTurnReporting(state).state
    }

    /// `startTurn` with the player-facing events retained — chiefly the
    /// Beginning Phase's Hold scores (630.2).
    public static func startTurnReporting(_ state: GameState) -> Outcome {
        var state = state
        var events: [PlayerInstruction] = []
        // Bounded rather than `while case .startOfTurn`: four steps exist
        // (515.1–515.4), so more than four iterations means a step failed
        // to advance the phase, and spinning forever would hide that.
        for _ in 0..<4 {
            guard case .startOfTurn = state.phase else { break }
            let outcome = advanceReporting(state)
            state = outcome.state
            events += outcome.events
        }
        return Outcome(state: state, events: events)
    }

    /// Rule 515.1, Awaken Phase: the Turn Player readies every Game Object
    /// they control that can be readied.
    ///
    /// Runes are included because a Rune is a Game Object (154.1) — this is
    /// what makes the Energy engine cycle: Runes exhausted last turn to pay
    /// costs stand back up now and can pay again (157.2.a). Leaving them
    /// out would mean a player's Rune Area drained permanently over a few
    /// turns.
    ///
    /// Note this readies by *controller*, not owner (183): a Unit whose
    /// control was taken by an opponent readies on that opponent's Awaken,
    /// not on its owner's.
    private static func awaken(_ state: inout GameState) {
        let turnPlayer = state.turnPlayer

        for (id, unit) in state.units where unit.controller == turnPlayer {
            state.units[id]?.isExhausted = false
        }
        for (id, gear) in state.gear where gear.controller == turnPlayer {
            state.gear[id]?.isExhausted = false
        }
        for (id, rune) in state.runes where rune.controller == turnPlayer {
            state.runes[id]?.isExhausted = false
        }
        state.zones[turnPlayer]?.legend.isExhausted = false
    }

    /// Rule 515.3, Channel Phase: the Turn Player channels 2 Runes from
    /// their Rune Deck (515.3.b), or 3 on their own first turn if they went
    /// second (646.6/647.7).
    ///
    /// These arrive **Ready** (606.2's "exhausted" is an effect-specified
    /// exception, and the Channel Phase specifies no such thing), so they
    /// add no Energy yet — see `GameActionApplier.applyExhaust`. A player
    /// who has channeled 2 Runes has 2 Runes, not 2 Energy.
    private static func channel(_ state: inout GameState) {
        let turnPlayer = state.turnPlayer
        let count = RuneChannelPace.runesToChannel(
            for: turnPlayer,
            turnOrder: state.turnOrder,
            completedTurns: state.completedChannelSteps[turnPlayer, default: 0]
        )

        // 606.3: Channel is a Limited Action, legal only when something
        // calls for it — 515.3.b is that something. Authorize before
        // applying so this goes through the same validated path a card
        // effect's "channel 1 rune" would, rather than reaching around it.
        let action = GameAction.channel(count: count, exhausted: false)
        state.authorize(action, for: turnPlayer)
        GameActionApplier.apply(action, to: &state, proposedBy: turnPlayer)

        state.completedChannelSteps[turnPlayer, default: 0] += 1
    }

    /// Rule 515.4, Draw Phase: the Turn Player draws 1 (515.4.b), then
    /// **every** player's Rune Pool empties as the phase ends (515.4.d/160).
    ///
    /// The emptying is all players', not just the Turn Player's — rule 160
    /// says "every player's Rune Pool empties at the end of each player's
    /// draw phase," so a defender who banked Power on the previous turn
    /// loses it here too.
    ///
    /// 646.7/647.7/648.7: in three- and four-player modes the player going
    /// first does not draw on their own first Draw Phase. **1v1 has no such
    /// rule** — 644.7/645.7 give the two-player modes only the extra-Rune
    /// clause — so the first player does draw on turn one of a 1v1.
    private static func drawStep(_ state: inout GameState) {
        let turnPlayer = state.turnPlayer

        if !isFirstTurnOfPlayerGoingFirst(state) {
            let action = GameAction.draw(count: 1)
            state.authorize(action, for: turnPlayer)                 // 591.2.a
            GameActionApplier.apply(action, to: &state, proposedBy: turnPlayer)
        }

        for player in state.turnOrder {
            state.zones[player]?.runePool = .empty                    // 515.4.d / 160
        }
    }

    /// Rule 646.7/647.7/648.7: the player going first skips the draw on
    /// their own first Draw Phase — **in 3+ player modes only**. The
    /// two-player modes (644.7/645.7) state only the extra-Rune clause, so
    /// gating on player count here is the difference between the rule and a
    /// plausible-sounding generalization of it.
    ///
    /// `completedChannelSteps` is the turn counter to read — the Channel
    /// Step immediately precedes this one and has already incremented, so a
    /// value of 1 means "this is that player's first turn."
    private static func isFirstTurnOfPlayerGoingFirst(_ state: GameState) -> Bool {
        guard state.turnOrder.count > 2 else { return false }
        guard state.turnOrder.first == state.turnPlayer else { return false }
        return state.completedChannelSteps[state.turnPlayer, default: 0] == 1
    }

    /// Rule 517, End of Turn Phase: Ending Step, Expiration Step, Cleanup
    /// Step, then the Turn Player becomes the next player in Turn Order
    /// (517.5) and the next turn's Awaken begins.
    ///
    /// 517.4's "if further damage or 'this turn' effects were generated,
    /// return to the Expiration Step" is not looped here: nothing in this
    /// engine generates effects during Expiration yet (the Effects pipeline
    /// doesn't execute — architecture.md item 7), so a loop would spin on
    /// unchanging state. Flagged rather than faked; when effect execution
    /// lands, this is the place that needs the loop.
    public static func endTurn(_ state: GameState) -> GameState {
        guard state.winner == nil else { return state }
        var state = state

        // 517.1 Ending Step: end-of-turn triggers. Nothing to run yet.
        //
        // The phase is moved through 517's steps as the work is done, not
        // set once at the end. `Cleanup` reads `phase` to decide whether a
        // Showdown may open (516.5), so leaving it at `.action` through the
        // Cleanup Step below would let the turn end by starting a fight.
        state.phase = .endOfTurn(.ending)

        // 517.2 Expiration Step.
        state.phase = .endOfTurn(.expiration)
        for (id, unit) in state.units {
            state.units[id]?.damage = 0                    // 517.2.a / 139.3.b.1
            state.units[id]?.grantedKeywords = []          // 517.2.b / 109
            _ = unit
        }
        for player in state.turnOrder {
            state.zones[player]?.runePool = .empty         // 517.2.c / 160
        }

        // 517.3 Cleanup Step.
        state.phase = .endOfTurn(.cleanup)
        state = Cleanup.run(state)

        // 517.5: the Turn Player becomes the next player in Turn Order.
        state.turnPlayerIndex = (state.turnPlayerIndex + 1) % state.turnOrder.count

        // 631: "once per Battlefield per turn" — the new turn is a new
        // turn, so every Battlefield is scoreable again. Cleared here
        // rather than at Beginning so a Conquer late in this turn can't be
        // re-scored by the same player before the turn actually ends.
        for battlefieldID in state.battlefieldControl.keys {
            state.battlefieldControl[battlefieldID]?.scoredThisTurnBy = []
        }

        state.phase = .startOfTurn(.awaken)
        return state
    }
}
