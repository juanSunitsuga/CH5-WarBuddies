/// Given a `GameState` snapshot and a proposed `GameAction`, decides
/// whether it's currently legal. This is what the OCR/event-inference
/// layer will call with candidate actions derived from observed table
/// deltas — see docs/architecture.md section 5 for the "untrusted
/// proposer" framing.
///
/// Only `standardMove` has real logic below, as a worked example of the
/// level of rigor expected — reference the exact rule for every branch.
/// Fill in the remaining cases in the build order from
/// docs/architecture.md (Play Card next, since it's the other half of the
/// two actions most directly observable from a physical table).
public enum LegalityValidator {
    public enum Failure: Error, Equatable {
        case notPlayersPriority
        case unitAlreadyExhausted(ObjectID)
        case unitNotFound(ObjectID)
        case destinationOccupiedByTwoOtherControllers(BattlefieldID)
        case moveOriginsMismatch  // 140.3.b requires same Destination, not same Origin — but all named units must actually exist and be movable
        /// Rule 589.2: this Limited Action was proposed without any rule or
        /// effect having called for it — nothing in
        /// `GameState.pendingLimitedActions` matches. The classic case:
        /// OCR observed a player draw a card whose "when I enter play, draw
        /// a card" trigger hasn't actually resolved yet.
        case limitedActionNotAuthorized(GameAction)
        case notImplemented
    }

    public static func validate(_ action: GameAction, in state: GameState, proposedBy player: PlayerID) -> Result<Void, Failure> {
        switch action {
        case .standardMove(let unitIDs, let destination):
            return validateStandardMove(unitIDs, destination: destination, in: state, player: player)

        // Rule 589.2: Limited Actions are never player-initiated at will —
        // every one of them is legal only if something already authorized
        // it (see `GameState.pendingLimitedActions`). The check is
        // identical across all of them; only *application* differs per
        // case, and only `.draw` has that built out so far.
        case .draw, .exhaust, .ready, .recycle, .discard, .stun, .reveal,
             .counter, .buff, .banish, .kill, .add, .channel, .burnOut:
            return validateLimitedAction(action, in: state, player: player)

        default:
            return .failure(.notImplemented)
        }
    }

    /// Rule 589.2: legal iff a rule or effect has already authorized this
    /// exact Limited Action for this player (`GameState.authorize(_:for:)`).
    private static func validateLimitedAction(
        _ action: GameAction,
        in state: GameState,
        player: PlayerID
    ) -> Result<Void, LegalityValidator.Failure> {
        guard state.pendingLimitedActions[player]?.contains(action) == true else {
            return .failure(.limitedActionNotAuthorized(action))
        }
        return .success(())
    }

    /// Rule 140: Standard Move.
    ///   - 140.1: only during the Turn Player's Action Phase, Neutral Open
    ///     state, not during a Showdown.
    ///   - 140.2: exhausting the unit(s) is the cost.
    ///   - 140.3: multiple units may move together to the *same*
    ///     Destination simultaneously; their Origins need not match.
    ///   - 140.4.a.1 / 610.2.a / 623.2: a Battlefield already occupied by
    ///     units from 2 *other* players is an invalid destination.
    private static func validateStandardMove(
        _ unitIDs: [ObjectID],
        destination: Location,
        in state: GameState,
        player: PlayerID
    ) -> Result<Void, LegalityValidator.Failure> {
        // 140.1.a/b/c: must be Neutral Open, and (for simplicity here) we
        // require it be this player's turn — team-mode exceptions to
        // "whose turn" are not yet modeled (see 516.2.b.1, 648.8.a).
        guard case .neutralOpen = state.turnState else {
            return .failure(.notPlayersPriority)
        }
        guard state.playerWithPriority(for: player) else {
            return .failure(.notPlayersPriority)
        }

        for unitID in unitIDs {
            guard let unit = state.units[unitID] else {
                return .failure(.unitNotFound(unitID))
            }
            guard !unit.isExhausted else {
                return .failure(.unitAlreadyExhausted(unitID))
            }
        }

        if case .battlefield(let battlefieldID) = destination {
            let controllersPresent = Set(
                state.units.values
                    .filter { $0.location == .battlefield(battlefieldID) }
                    .map(\.controller)
            )
            let otherControllers = controllersPresent.subtracting([player])
            if otherControllers.count >= 2 {
                return .failure(.destinationOccupiedByTwoOtherControllers(battlefieldID))
            }
        }

        return .success(())
    }
}

private extension GameState {
    /// Convenience placeholder — real Priority derivation should route
    /// through `TurnState.playerWithPriority(turnPlayer:)`; this exists so
    /// the validator above type-checks without redefining that logic
    /// inline. Revisit once `GameState` exposes turn-player lookups more
    /// fully (e.g. team-mode co-priority per 516.2.b.1).
    func playerWithPriority(for player: PlayerID) -> Bool {
        turnState.playerWithPriority(turnPlayer: turnPlayer) == player
    }
}
