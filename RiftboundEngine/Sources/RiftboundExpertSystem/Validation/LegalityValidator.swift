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
        /// Rule 130.2: how many Runes were physically Exhausted at the
        /// moment this Play was observed doesn't match the card's Energy
        /// cost — Energy is paid by Exhausting Runes, so playing a card
        /// costing `required` should correspond to exactly that many
        /// Runes going from Ready to Exhausted. Only checked when the
        /// proposer actually supplied `GameAction.play`'s
        /// `observedExhaustedRuneCount` — see that field's doc comment.
        case exhaustedRuneCountMismatch(required: Int, observed: Int)
        /// Rule 509.1.a: the turn is Closed (`.neutralClosed`/`.showdownClosed`
        /// — a Chain currently exists) and this card carries no
        /// `Keyword.reaction` (725) — only Reaction-tagged cards/abilities
        /// may respond to an existing window. (Whether `player` is even
        /// allowed to act right now at all is a separate check —
        /// `Failure.notPlayersPriority`, from `TurnState.playerWithPriority`.)
        case reactionRequired
        /// Rule 508.1.a: a Showdown is in progress with no Chain yet
        /// (`.showdownOpen`) and this card carries neither `Keyword.action`
        /// (718) nor `Keyword.reaction` (725) — only Action- or
        /// Reaction-tagged cards/abilities may open the Showdown's Chain.
        case actionOrReactionRequired
        /// Rule 589.2: this Limited Action was proposed without any rule or
        /// effect having called for it — nothing in
        /// `GameState.pendingLimitedActions` matches. The classic case:
        /// OCR observed a player draw a card whose "when I enter play, draw
        /// a card" trigger hasn't actually resolved yet.
        case limitedActionNotAuthorized(GameAction)
        /// Rule 516.1/140.1.a: this action belongs to the Action Phase, and
        /// the turn hasn't reached it (or has left it). Everything before
        /// the Action Phase — Awaken, Beginning, Channel, Draw — is fixed
        /// and automatic (515), so a player physically playing a card
        /// during it is acting out of turn structure, not merely early.
        case notActionPhase(Phase)
        /// Rule 140.4: a Standard Move's Destination is restricted to Base
        /// → Battlefield and Battlefield → Base. Battlefield → Battlefield
        /// requires Ganking (140.4.c/722), and Base → Base isn't a Move at
        /// all.
        case illegalMoveDestination(from: Location, to: Location)
        /// Rule 594.3: a Recycle used as a cost has to be completable — the
        /// player has no Rune of this Domain in their Rune Area to send
        /// back to the Rune Deck, so the Power it would produce can't be
        /// paid for.
        case noRuneOfDomainAvailable(Domain)
        /// Rule 633: the game is over. Nothing further is legal.
        case gameAlreadyWon(PlayerID)
        case notImplemented
    }

    public static func validate(_ action: GameAction, in state: GameState, proposedBy player: PlayerID) -> Result<Void, Failure> {
        // Rule 633: a player already won — the game ended immediately, so
        // nothing after it is legal regardless of how plausible it looks.
        if let winner = state.winner {
            return .failure(.gameAlreadyWon(winner))
        }

        switch action {
        case .play(let card, let destination, let additionalChoices, let observedExhaustedRuneCount):
            return validatePlay(card: card, destination: destination, additionalChoices: additionalChoices, observedExhaustedRuneCount: observedExhaustedRuneCount, in: state, player: player)

        case .standardMove(let unitIDs, let destination):
            return validateStandardMove(unitIDs, destination: destination, in: state, player: player)

        case .pass:
            return validatePass(in: state, player: player)

        // Rule 516.6: ending the Action Phase is the Turn Player's to
        // declare, and only from within the Action Phase — there is
        // nothing to end before it starts.
        case .endTurn:
            guard case .action = state.phase else {
                return .failure(.notActionPhase(state.phase))
            }
            guard state.turnPlayer == player else {
                return .failure(.notPlayersPriority)
            }
            return .success(())

        // Rule 589.2: Limited Actions are never player-initiated at will —
        // every one of them is legal only if something already authorized
        // it (see `GameState.pendingLimitedActions`). The check is
        // identical across all of them; only *application* differs per
        // case, and only `.draw` has that built out so far.
        case .recycleRune(let domain):
            return validateRuneAbility(in: state, player: player) {
                // 594.3: "the action must be able to be completed for the
                // cost to be paid" — no matching Rune, no Power.
                state.runes.values.contains { $0.controller == player && $0.domain == domain }
                    ? nil
                    : .noRuneOfDomainAvailable(domain)
            }

        case .exhaust(let objects):
            // 157.2.a's `[T]: Add [1]` is likewise this Rune's own ability,
            // so exhausting your own Runes is discretionary. Exhausting
            // anything else stays a Limited Action (592) — an opponent's
            // Unit doesn't exhaust because you decided so.
            if !objects.isEmpty, objects.allSatisfy({ state.runes[$0]?.controller == player }) {
                return validateRuneAbility(in: state, player: player) { nil }
            }
            return validateLimitedAction(action, in: state, player: player)

        case .draw, .ready, .recycle, .discard, .stun, .reveal,
             .counter, .buff, .banish, .kill, .add, .channel, .burnOut:
            return validateLimitedAction(action, in: state, player: player)

        default:
            return .failure(.notImplemented)
        }
    }

    /// Rule 555–561: Playing a Card (the legality-relevant substeps only —
    /// 562's "would this create an illegal state" and actually pushing the
    /// item onto a Chain (558/563.2.a) aren't modeled here, see
    /// `applyPlay`'s doc comment for why — this only decides whether the
    /// attempt is legal, `GameActionApplier` still resolves immediately
    /// rather than queuing).
    ///   - 516.2.b/512.1.a: Playing is a Discretionary Action — only legal
    ///     with Priority, which `TurnState.playerWithPriority` already
    ///     derives correctly for all four states (Turn Player in Neutral
    ///     Open, the Chain's `activePlayer` when Closed, the Showdown's
    ///     `focusPlayer` when Open).
    ///   - 509.1.a/508.1.a: which cards are eligible depends on which of
    ///     the four `TurnState` cases this is — Neutral Open has no
    ///     keyword restriction at all (it's the normal "just play a card"
    ///     state); Neutral Closed and Showdown Closed require
    ///     `Keyword.reaction`; Showdown Open requires `Keyword.action` or
    ///     `Keyword.reaction`. See `TurnState`'s own doc comment for the
    ///     rule citations per case.
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
    ///   - 130.2: when `observedExhaustedRuneCount` is supplied, it must
    ///     equal the card's Energy cost exactly — the physical
    ///     corroboration that Energy really was paid by Exhausting that
    ///     many Runes, not just an abstract pool balance. Skipped entirely
    ///     when `nil` (no observation to check against).
    private static func validatePlay(
        card cardID: ObjectID,
        destination: PlayDestination,
        additionalChoices: [ObjectID],
        observedExhaustedRuneCount: Int?,
        in state: GameState,
        player: PlayerID
    ) -> Result<Void, LegalityValidator.Failure> {
        // 516.1/148: cards are played during the Action Phase. The four
        // Start of Turn steps are fixed and automatic (515) and grant no
        // window to act in, so a card played during them isn't early — it's
        // out of structure. A Showdown is *inside* the Action Phase, so
        // this doesn't block Reactions during one.
        guard case .action = state.phase else {
            return .failure(.notActionPhase(state.phase))
        }
        guard state.playerWithPriority(for: player) else {
            return .failure(.notPlayersPriority)
        }
        guard let card = state.zones[player]?.hand.first(where: { $0.id == cardID }) else {
            return .failure(.cardNotInHand(cardID))
        }

        switch state.turnState {
        case .neutralOpen:
            break  // 516.2.b: no keyword restriction — this is the normal play window.
        case .neutralClosed, .showdownClosed:
            guard card.keywords.contains(.reaction) else {
                return .failure(.reactionRequired)
            }
        case .showdownOpen:
            guard card.keywords.contains(.action) || card.keywords.contains(.reaction) else {
                return .failure(.actionOrReactionRequired)
            }
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

        if let observedExhaustedRuneCount, observedExhaustedRuneCount != energyCost {
            return .failure(.exhaustedRuneCountMismatch(required: energyCost, observed: observedExhaustedRuneCount))
        }

        return .success(())
    }

    /// Rule 540.4/553.4: Pass is legal whenever `player` currently has
    /// Priority — unlike `.play`, it isn't keyword-gated by `TurnState`;
    /// declining to act is always available to whoever may currently act,
    /// in any of the four `TurnState` cases (including when there's no
    /// Chain to pass on at all, `.neutralOpen`/`.showdownOpen` —
    /// `ChainResolver.pass` just no-ops there rather than this being
    /// illegal to attempt).
    private static func validatePass(in state: GameState, player: PlayerID) -> Result<Void, LegalityValidator.Failure> {
        guard state.playerWithPriority(for: player) else {
            return .failure(.notPlayersPriority)
        }
        return .success(())
    }

    /// Rule 157.2 + 577: a Rune's two intrinsic abilities —
    /// `[T]: Add [1]` and `Recycle this: Add [C]` — are **Activated
    /// Abilities** (577.2 recognizes them by the `:`), whose costs happen
    /// to be Exhausting and Recycling. Activating an ability is a
    /// Discretionary Action (589.1), so these need Priority and a legal
    /// window, *not* an entry in `pendingLimitedActions`.
    ///
    /// This distinction is why the pipeline could not produce Energy or
    /// Power at all before: both actions were gated on 589.2 authorization
    /// that nothing ever granted, so every observed rune turn or recycle
    /// came back "nothing has called for that action yet." 594.2.a is
    /// explicit that Recycling happens when instructed by effects **or
    /// costs**, and paying for a card is a cost.
    ///
    /// Priority is the only timing gate, deliberately wider than 589.1.a's
    /// "Neutral Open State": costs are paid *during* the process of playing
    /// a card (560–561), including a Reaction played into a Chain or a
    /// Showdown, so restricting rune payment to Neutral Open would make
    /// those unplayable.
    ///
    /// 577.3 says Activated Abilities use the Chain. These two resolve
    /// immediately instead — putting "add 1 energy" on the Chain would
    /// require a full pass-around before the Energy existed to spend, and
    /// physically the player just turns the rune as they pay. Noted here
    /// rather than silently diverged from.
    private static func validateRuneAbility(
        in state: GameState,
        player: PlayerID,
        costCheck: () -> Failure?
    ) -> Result<Void, LegalityValidator.Failure> {
        guard state.playerWithPriority(for: player) else {
            return .failure(.notPlayersPriority)
        }
        if let failure = costCheck() {
            return .failure(failure)
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

    /// Rule 140: Standard Move.
    ///   - 140.1: only during the Turn Player's Action Phase, Neutral Open
    ///     state, not during a Showdown.
    ///   - 140.2: exhausting the unit(s) is the cost.
    ///   - 140.3: multiple units may move together to the *same*
    ///     Destination simultaneously; their Origins need not match.
    ///   - 140.4: the Destination is restricted — Base → Battlefield and
    ///     Battlefield → Base only, unless the Unit has Ganking (140.4.c/
    ///     722), which additionally allows Battlefield → Battlefield.
    ///   - 140.4.a.1 / 610.2.a / 623.2: a Battlefield already occupied by
    ///     units from 2 *other* players is an invalid destination.
    ///
    /// One Move goes to one Destination (140.3.a), and `destination` being
    /// a single value is what enforces that — a player cannot split a Move
    /// across two Battlefields, which is why each Showdown is about exactly
    /// one Battlefield.
    private static func validateStandardMove(
        _ unitIDs: [ObjectID],
        destination: Location,
        in state: GameState,
        player: PlayerID
    ) -> Result<Void, LegalityValidator.Failure> {
        // 140.1.a: only during the player's Action Phase.
        guard case .action = state.phase else {
            return .failure(.notActionPhase(state.phase))
        }
        // 140.1.b/c: not during a Closed State, and not during a Showdown —
        // both of which `.neutralOpen` excludes in one check. This is why a
        // Showdown is a real pause: you can't keep moving units into it.
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
            guard isLegalMove(from: unit.location, to: destination, unit: unit) else {
                return .failure(.illegalMoveDestination(from: unit.location, to: destination))
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

    /// Rule 140.4: which Origin → Destination pairs a Standard Move allows.
    ///
    ///   - 140.4.a: Base → Battlefield.
    ///   - 140.4.b: Battlefield → Base.
    ///   - 140.4.c.1: Battlefield → Battlefield, **only** with Ganking (722).
    ///
    /// Base → Base is absent from the rule and is not a Move at all. A Unit
    /// moving to the Battlefield it is already at is likewise rejected: it
    /// would pay the Exhaust cost (140.2) for no change of Location, and
    /// in practice it means the camera saw a unit jitter rather than move.
    private static func isLegalMove(from origin: Location, to destination: Location, unit: Unit) -> Bool {
        switch (origin, destination) {
        case (.base, .battlefield):
            return true                                    // 140.4.a
        case (.battlefield, .base):
            return true                                    // 140.4.b
        case (.battlefield(let from), .battlefield(let to)):
            guard from != to else { return false }
            return unit.printedKeywords.contains(.ganking)
                || unit.grantedKeywords.contains(.ganking)  // 140.4.c.1
        case (.base, .base):
            return false
        }
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
