/// Given a `GameState` snapshot and a proposed `GameAction`, decides
/// whether it's currently legal. This is what the OCR/event-inference
/// layer will call with candidate actions derived from observed table
/// deltas — see docs/architecture.md section 5 for the "untrusted
/// proposer" framing.
///
/// `standardMove`, `draw`/other Limited Actions, and `play` have real logic
/// below — `standardMove` was the original worked example of the level of
/// rigor expected (reference the exact rule for every branch); `play`
/// follows the same pattern, citing rules 555–563. Fill in the remaining
/// cases in the build order from docs/architecture.md.
public enum LegalityValidator {
    public enum Failure: Error, Equatable {
        case notPlayersPriority
        case unitAlreadyExhausted(ObjectID)
        case unitNotFound(ObjectID)
        case destinationOccupiedByTwoOtherControllers(BattlefieldID)
        case moveOriginsMismatch  // 140.3.b requires same Destination, not same Origin — but all named units must actually exist and be movable
        /// Rule 555/558: the proposed card isn't in the proposing player's
        /// Hand — either it's already been played, or the observed event
        /// misidentified which card moved.
        case cardNotInHand(ObjectID)
        /// Rule 559.2: a Unit must be given a real board Location to enter
        /// (`.none` is only valid for Spells/abilities, which have no board
        /// form).
        case invalidPlayDestination(PlayDestination)
        /// Rule 560–561: the player's Rune Pool doesn't have enough Energy
        /// to pay the card's cost.
        case insufficientEnergy(required: Int, available: Int)
        /// Rule 560–561/130.3: the player's Rune Pool doesn't have enough
        /// Power matching the card's `eligibleDomains` — either too few
        /// Runes of any eligible Domain were Recycled, or the wrong
        /// Domain(s) were (e.g. Recycling 2 Fury when the card needs 2
        /// Chaos; Recycling 1 Fury + 1 Chaos when it needs 2 of a single
        /// Domain). `available` counts only pool entries that actually
        /// match — non-matching entries in the pool don't count toward it
        /// even though they're real, spendable Power for some other card.
        case insufficientPower(required: Int, available: Int)
        /// Rule 130.2/130.3: the Rune being Recycled was already Exhausted
        /// when observed — it already paid an Energy cost this cycle, so
        /// Recycling it too would spend one physical Rune for both Energy
        /// and Power. See `GameAction.recycleRune`'s doc comment.
        case recycledExhaustedRune
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
        case .play(let card, let destination, let additionalChoices):
            return validatePlay(card: card, destination: destination, additionalChoices: additionalChoices, in: state, player: player)

        case .standardMove(let unitIDs, let destination):
            return validateStandardMove(unitIDs, destination: destination, in: state, player: player)

        case .recycleRune(_, let wasExhausted):
            return validateRecycleRune(action, wasExhausted: wasExhausted, in: state, player: player)

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

    /// Rule 555–561: Playing a Card (the legality-relevant substeps only —
    /// 562's "would this create an illegal state" and the Chain/Reaction
    /// machinery of 558/563.2.a aren't modeled here, see `applyPlay`'s doc
    /// comment for why).
    ///   - 516.2.b: Playing is a Discretionary Action — only legal with
    ///     Priority. Restricted to Neutral Open here, same simplification
    ///     `validateStandardMove` makes (Showdown/Focus-based Play isn't
    ///     modeled yet).
    ///   - 555.1/558: the card must actually be in the player's Hand.
    ///   - 559.2: a Unit must be given a real Location (not `.none`); a
    ///     Battlefield destination already Controlled by two *other*
    ///     players is invalid, the same 610.2.a/623.2 restriction
    ///     `validateStandardMove` checks for Move.
    ///   - 560–561: the card's Energy cost must be payable from the
    ///     player's Rune Pool, and its Power cost from `RunePool.power`,
    ///     matched against `Cost.eligibleDomains` (any combination of
    ///     those Domains, summing to `Cost.powerCost` — see the type's
    ///     own doc comment for why this isn't positional).
    private static func validatePlay(
        card cardID: ObjectID,
        destination: PlayDestination,
        additionalChoices: [ObjectID],
        in state: GameState,
        player: PlayerID
    ) -> Result<Void, LegalityValidator.Failure> {
        guard case .neutralOpen = state.turnState else {
            return .failure(.notPlayersPriority)
        }
        guard state.playerWithPriority(for: player) else {
            return .failure(.notPlayersPriority)
        }
        guard let card = state.zones[player]?.hand.first(where: { $0.id == cardID }) else {
            return .failure(.cardNotInHand(cardID))
        }

        switch (card.type, destination) {
        case (.unit, .none):
            return .failure(.invalidPlayDestination(destination))
        case (.gear, .battlefield):
            // 144.2: Gear always enters at the player's Base, never a
            // Battlefield — `applyPlay` corrects the Location regardless,
            // but a Battlefield destination for Gear signals the proposer
            // misread the observed event, so reject rather than silently
            // reinterpret it.
            return .failure(.invalidPlayDestination(destination))
        default:
            break
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

        let energyCost = card.cost.energy
        let availableEnergy = state.zones[player]?.runePool.energy ?? 0
        guard availableEnergy >= energyCost else {
            return .failure(.insufficientEnergy(required: energyCost, available: availableEnergy))
        }

        let powerCost = card.cost.powerCost
        if powerCost > 0 {
            let eligibleDomains = card.cost.eligibleDomains
            let availablePower = (state.zones[player]?.runePool.power ?? []).filter { powerType in
                switch powerType {
                case .universal: return true
                case .domain(let domain): return eligibleDomains.contains(domain)
                }
            }.count
            guard availablePower >= powerCost else {
                return .failure(.insufficientPower(required: powerCost, available: availablePower))
            }
        }

        return .success(())
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

    /// Rule 130.3/589.2: everything `validateLimitedAction` already checks
    /// (589.2 authorization) for `.recycleRune`, plus the one thing that's
    /// specific to it: the Rune must have been Ready, not already
    /// Exhausted, at the moment it was observed moving to the Rune Deck
    /// (130.2/130.3 — see `Failure.recycledExhaustedRune`'s doc comment for
    /// why an Exhausted Rune can't also be Recycled). Checked before
    /// authorization so a double-spend attempt is reported as exactly
    /// that, not as "nothing called for this," which would be true but
    /// miss the actual problem.
    private static func validateRecycleRune(
        _ action: GameAction,
        wasExhausted: Bool,
        in state: GameState,
        player: PlayerID
    ) -> Result<Void, LegalityValidator.Failure> {
        guard !wasExhausted else {
            return .failure(.recycledExhaustedRune)
        }
        return validateLimitedAction(action, in: state, player: player)
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
