/// Rule 518–526: the state-based-action sweep. MUST be invoked after every:
/// Chain item resolution, Move completion, Showdown completion, Combat
/// completion (rule 519). See CLAUDE.md point 3 — this is intentionally a
/// single pure function; do not inline partial versions elsewhere.
///
/// Steps run in the fixed order given by the rule numbering (520–526).
/// Each is left as a documented TODO for now — get the *shape* (single
/// entry point, fixed order, pure function) locked in and tested with
/// no-op cases before filling in logic, per the build order in
/// docs/architecture.md.
public enum Cleanup {
    public static func run(_ state: GameState) -> GameState {
        var state = state
        killLethallyDamagedUnits(&state)        // 520
        clearStaleCombatRoles(&state)            // 521
        applyStateBasedEffects(&state)           // 522 ("While"/"As long as" effects)
        removeOrphanedHiddenCards(&state)         // 523
        markPendingCombats(&state)                 // 524
        releaseControlOfAbandonedBattlefields(&state) // 181.4.d — see below
        openShowdownForUncontrolledContested(&state) // 525
        beginCombatIfPending(&state)                  // 526
        return state
    }

    /// Rule 181.4.d: "If a player has no Units at a Battlefield, they have
    /// no Control of that Battlefield." 181.5 makes Control "a constant
    /// state with no reliance on timing" — i.e. a state-based fact, which
    /// is exactly what a Cleanup exists to reconcile, so it belongs here
    /// even though 518–526 never numbers it as a step.
    ///
    /// Without it, Control could outlive the Units that established it: a
    /// player whose Units died elsewhere or were Recalled stayed the
    /// `controller` of a Battlefield they had abandoned. That is not just
    /// a stale field — 525 only opens its Showdown for a Contested
    /// Battlefield with **no** Controller, so an opponent moving into that
    /// abandoned Battlefield got no Showdown, never established Control,
    /// and could never Conquer it. The Battlefield became permanently
    /// unwinnable while looking perfectly normal on the table.
    ///
    /// 181.4.b is the exception: "A player maintains control of a
    /// Battlefield while it is being Contested by an opponent," and 181.4.a
    /// scopes Control-by-presence to "outside of Combat" — so a Battlefield
    /// with a Combat pending keeps its Controller until that Combat
    /// resolves.
    private static func releaseControlOfAbandonedBattlefields(_ state: inout GameState) {
        for battlefieldID in state.battlefields.keys {
            guard let controller = state.battlefieldControl[battlefieldID]?.controller else { continue }
            guard state.battlefieldControl[battlefieldID]?.combatPending != true else { continue }  // 181.4.b

            let stillPresent = state.units.values.contains {
                $0.location == .battlefield(battlefieldID) && $0.controller == controller
            }
            if !stillPresent {
                state.battlefieldControl[battlefieldID]?.controller = nil
            }
        }
    }

    /// 520: any Unit with nonzero damage >= current Might is killed and
    /// placed in its owner's Trash (not controller's — rule 107.1.d).
    private static func killLethallyDamagedUnits(_ state: inout GameState) {
        // TODO: requires the Layers-aware Might calculator (637) to get
        // "current Might" correctly, not just `baseMight`. Stub until
        // that's built; do not approximate with baseMight here, since a
        // unit debuffed this turn could be lethal at a lower threshold
        // than its printed stat suggests.
    }

    /// 521: strip Attacker/Defender designation from units no longer
    /// present at a Battlefield where Combat is occurring.
    private static func clearStaleCombatRoles(_ state: inout GameState) {
        // TODO
    }

    /// 522: recognize and execute "While"/"As long as" state-based effects.
    private static func applyStateBasedEffects(_ state: inout GameState) {
        // TODO — depends on the ability-registry / NLP-parsed effect layer
        // existing first.
    }

    /// 523: a Hidden card at a Battlefield with no Unit from its controller
    /// present is removed to its owner's Trash; this can uncontrol the
    /// Battlefield if it wasn't already handled by a Conquer step.
    private static func removeOrphanedHiddenCards(_ state: inout GameState) {
        // TODO
    }

    /// 524: mark Combat as Pending wherever two opposing players' Units
    /// share a Battlefield. Combat stays Pending as long as that's true
    /// (524.1) — this is a status flag, not an immediate trigger.
    private static func markPendingCombats(_ state: inout GameState) {
        for battlefieldID in state.battlefields.keys {
            let controllers = Set(
                state.units.values
                    .filter { $0.location == .battlefield(battlefieldID) }
                    .map(\.controller)
            )
            state.battlefieldControl[battlefieldID, default: BattlefieldControl()].combatPending = controllers.count >= 2
        }
    }

    /// 525: in a Neutral Open state, if any Battlefield is Contested with
    /// no current Controller, the Turn Player picks one and a Showdown
    /// begins there (not a Combat — no opposing units yet, per 613.1: this
    /// only applies when the Battlefield has no Units present from any
    /// player other than those that just moved — i.e. `combatPending` is
    /// false, which distinguishes this from the 526 case).
    ///
    /// 549: the player who applied Contested status gains Focus.
    /// 550.2: since this Showdown is not part of Combat, all players are
    /// Relevant Players.
    private static func openShowdownForUncontrolledContested(_ state: inout GameState) {
        guard case .neutralOpen = state.turnState else { return }
        // 516.5: Showdowns occur as a result of Discretionary Actions taken
        // during the Action Phase. Cleanup also runs from the End of Turn's
        // Cleanup Step (517.3), and without this guard a Battlefield left
        // Contested at end of turn would open a Showdown *there* — after
        // the turn had ended, with the state then handed to the next
        // player mid-Showdown.
        guard case .action = state.phase else { return }

        // 525: "the Turn Player chooses one" — the choice among multiple
        // simultaneously-qualifying Battlefields is a genuine player
        // decision this engine doesn't yet have a way to solicit
        // mid-Cleanup; taking the first candidate is a placeholder until
        // that choice can be threaded through (see `ChoicePrompt`).
        guard let battlefieldID = state.battlefields.keys.first(where: { id in
            let control = state.battlefieldControl[id]
            return control?.isContested == true
                && control?.controller == nil
                && control?.combatPending != true
        }) else { return }

        guard let focusPlayer = state.battlefieldControl[battlefieldID]?.contestedBy else { return }

        let showdown = Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: focusPlayer,
            relevantPlayers: Set(state.turnOrder)
        )
        state.turnState = .showdownOpen(showdown)
    }

    /// 526: in a Neutral Open state, if Combat is Pending at one or more
    /// Battlefields, the Turn Player picks one and Combat begins there —
    /// the counterpart to 525, for when the Battlefield *does* already
    /// have an opposing Unit present (`combatPending == true`, set by
    /// `markPendingCombats` just above). Scoped to opening the Showdown
    /// only, same level 525 stops at — the internal Combat Step sequence
    /// (624–628: establishing Attacker/Defender roles on the Units
    /// themselves, Assault/Shield, damage) is a separate, not-yet-modeled
    /// piece (`CombatStep` has no home in `GameState` yet); flagging
    /// rather than half-building it here.
    ///
    /// - 181.3.a/625.1.a.1: the player who most recently applied Contested
    ///   status to this Battlefield (`contestedBy`) is the Attacker — same
    ///   signal 525 already uses for Focus, since 549 grants Focus to that
    ///   same player. If `contestedBy` is missing or stale (doesn't match
    ///   either of the two controllers now present — e.g. Combat became
    ///   Pending some other way than a fresh Move/Play), there's no
    ///   reliable Attacker signal to act on, so this is skipped rather
    ///   than guessed at.
    /// - 550.2: unlike 525's standalone Showdown, only the two combatants
    ///   are Relevant Players here — a Combat Showdown does not open to
    ///   the whole table.
    /// - Team modes (Skirmish/War, 646–647) can have more than two
    ///   controllers at a Battlefield; `combatPending` only requires 2+,
    ///   but choosing a single Attacker/Defender pair from 3+ is a real
    ///   rules question this doesn't attempt — skipped when there isn't
    ///   exactly two.
    private static func beginCombatIfPending(_ state: inout GameState) {
        guard case .neutralOpen = state.turnState else { return }
        guard case .action = state.phase else { return }   // 516.5, same as 525 above

        // Same placeholder as 525: the choice among multiple simultaneously
        // Combat-Pending Battlefields is a genuine player decision this
        // engine doesn't yet have a way to solicit mid-Cleanup.
        guard let battlefieldID = state.battlefields.keys.first(where: {
            state.battlefieldControl[$0]?.combatPending == true
        }) else { return }

        let controllersPresent = Set(
            state.units.values
                .filter { $0.location == .battlefield(battlefieldID) }
                .map(\.controller)
        )
        guard controllersPresent.count == 2 else { return }

        guard let attacker = state.battlefieldControl[battlefieldID]?.contestedBy,
              controllersPresent.contains(attacker),
              let defender = controllersPresent.first(where: { $0 != attacker }) else {
            return
        }

        let showdown = Showdown(
            origin: .combat(attacker: attacker, defender: defender, battlefield: battlefieldID),
            focusPlayer: attacker,           // 549
            relevantPlayers: [attacker, defender]  // 550.2
        )
        state.turnState = .showdownOpen(showdown)
    }
}
