/// Rule 629–633: the only two ways a player earns Points.
///
///   - **Hold** (630.2): you Control a Battlefield during your Beginning
///     Phase. Passive — you scored it by still being there.
///   - **Conquer** (630.1): you gain Control of a Battlefield you have not
///     already Scored this turn. Active — in practice, winning a Showdown
///     as the attacker, which by 627.3 means your Units are the only ones
///     left standing there.
///
/// Both are capped by 631 at once per Battlefield per player per turn,
/// tracked in `BattlefieldControl.scoredThisTurnBy` and cleared by
/// `TurnSequencer.endTurn`.
///
/// Returns the `PlayerInstruction.scored`/`.gameWon` events rather than
/// only mutating, because scoring is something the player at the table
/// needs told — a Conquer that silently ticks a counter is exactly the
/// moment a physical game desyncs from the engine.
public enum Scoring {
    /// What a scoring pass produced, so callers can both commit the state
    /// and report it.
    public struct Outcome: Sendable {
        public var state: GameState
        public var events: [PlayerInstruction]
    }

    /// Rule 515.2.b.1/630.2: Hold. At the Turn Player's Beginning Phase,
    /// every Battlefield they Control scores them a Point.
    ///
    /// Control here is `BattlefieldControl.controller`, not "has units
    /// present" — 181.2 makes Control its own tracked status, and a
    /// Contested Battlefield still has whoever last established Control as
    /// its `controller` until a Conquer changes it (627.3.a).
    public static func scoreHolds(_ state: GameState) -> GameState {
        scoreHoldsReporting(state).state
    }

    /// `scoreHolds` with the player-facing events retained.
    public static func scoreHoldsReporting(_ state: GameState) -> Outcome {
        var state = state
        var events: [PlayerInstruction] = []
        let turnPlayer = state.turnPlayer

        // Sorted for determinism: `battlefieldControl` is a Dictionary, and
        // with two Battlefields both scoreable the order decides which one
        // earns the Final Point — that must not vary run to run.
        for battlefieldID in state.battlefields.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            guard state.battlefieldControl[battlefieldID]?.controller == turnPlayer else { continue }
            events += score(battlefieldID, by: turnPlayer, method: .hold, in: &state)
        }

        return Outcome(state: state, events: events)
    }

    /// Rule 630.1: Conquer. `player` has just gained Control of
    /// `battlefield` — award the Point if they haven't already Scored it
    /// this turn (631).
    public static func scoreConquer(
        _ battlefield: BattlefieldID,
        by player: PlayerID,
        in state: inout GameState
    ) -> [PlayerInstruction] {
        score(battlefield, by: player, method: .conquer, in: &state)
    }

    private enum Method {
        case hold      // 630.2
        case conquer   // 630.1
    }

    /// Rule 632: the shared body of both scoring methods.
    ///
    /// 632.1.b's Final Point restriction is the subtle part. When a player
    /// is one Point from the Victory Score:
    ///   - Scoring through **Hold** takes the Final Point outright
    ///     (632.1.b.1).
    ///   - Scoring through **Conquer** takes it only if they have Scored
    ///     *every* Battlefield this turn, by either method (632.1.b.2).
    ///     Otherwise they draw a card instead of earning the Point — the
    ///     game does not end on a lone Conquer.
    private static func score(
        _ battlefieldID: BattlefieldID,
        by player: PlayerID,
        method: Method,
        in state: inout GameState
    ) -> [PlayerInstruction] {
        guard state.winner == nil else { return [] }

        // 631: once per Battlefield per turn, from either method.
        var control = state.battlefieldControl[battlefieldID] ?? BattlefieldControl()
        guard !control.scoredThisTurnBy.contains(player) else { return [] }
        control.scoredThisTurnBy.insert(player)
        state.battlefieldControl[battlefieldID] = control

        let current = state.scores[player, default: 0]
        let isFinalPoint = current + 1 >= state.victoryScore

        if isFinalPoint, method == .conquer, !hasScoredEveryBattlefield(player, in: state) {
            // 632.1.b.2: no Point — a card instead. `.draw` is a Limited
            // Action (589.2), so authorize it rather than dealing the card
            // directly; the player still has to physically draw, and the
            // validator still has to see it.
            state.authorize(.draw(count: 1), for: player)
            return [.actionAccepted(
                .draw(count: 1),
                followUp: FollowUp(description: "Conquering doesn't take the final point unless you've scored every battlefield this turn — draw a card instead.")
            )]
        }

        state.scores[player] = current + 1
        var events: [PlayerInstruction] = [
            .scored(player: player, battlefield: battlefieldID, newTotal: current + 1)
        ]

        // 632.2: Score abilities trigger at the Battlefield that Scored —
        // Conquer abilities on a Conquer, Hold abilities on a Hold. Not
        // dispatched here: nothing executes ability effects yet
        // (architecture.md item 7). Flagged at the site where they belong.

        // 633: reaching the Victory Score wins immediately.
        if current + 1 >= state.victoryScore {
            state.winner = player
            events.append(.gameWon(player: player))
        }

        return events
    }

    /// Rule 632.1.b.2: "has Scored every Battlefield through either method
    /// this turn."
    private static func hasScoredEveryBattlefield(_ player: PlayerID, in state: GameState) -> Bool {
        !state.battlefields.isEmpty && state.battlefields.keys.allSatisfy {
            state.battlefieldControl[$0]?.scoredThisTurnBy.contains(player) == true
        }
    }
}
