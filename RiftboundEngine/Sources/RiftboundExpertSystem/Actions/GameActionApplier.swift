/// Mutates a `GameState` to reflect an already-validated `GameAction` — the
/// counterpart to `LegalityValidator` (which only ever answers "is this
/// legal right now," never touches state). Callers must run this only
/// through `GameStateStore.mutate`, per CLAUDE.md point 2.
///
/// `standardMove` and `draw` are implemented below, mirroring
/// `LegalityValidator`'s scope — fill in the remaining `GameAction` cases
/// in the same build order once each has real validator logic (CLAUDE.md
/// point 4, docs/architecture.md section 7).
public enum GameActionApplier {
    /// Applies `action` to `state` in place. Callers are responsible for
    /// having already confirmed legality via `LegalityValidator` — this
    /// performs no validation of its own.
    ///
    /// `abilityInstructions` is only meaningful for `.play`: the played
    /// card's ability, already parsed by the caller (`GameEngine`, via
    /// `ActionTranslating.parseAbility`) *before* calling this function —
    /// this layer stays pure/synchronous and never talks to the NLP layer
    /// itself (CLAUDE.md point 3). A Unit executes it immediately; a Spell
    /// carries it on the `ChainItem` it pushes, for `applyResolvedChainItem`
    /// to execute once the item actually resolves. Every other action
    /// ignores this parameter — defaulted so they don't need to pass one.
    ///
    /// Returns any `PlayerInstruction`s the application produced. Most
    /// actions produce none; the ones that do are the ones that reach
    /// scoring — ending a Showdown resolves a Combat, which can Conquer a
    /// Battlefield (630.1) and even win the game (633), and ending a turn
    /// runs the next player's Beginning Phase, which Holds (630.2). Those
    /// are consequences of the action rather than the action itself, so
    /// they can't be derived by the caller from the `GameAction` alone.
    /// An ability's own outcome (e.g. "Drew 1 card") is a separate channel
    /// — see `GameState.abilityOutcomeSummaries`.
    @discardableResult
    public static func apply(
        _ action: GameAction,
        to state: inout GameState,
        proposedBy player: PlayerID,
        abilityInstructions: [EffectInstruction] = []
    ) -> [PlayerInstruction] {
        switch action {
        case .play(let card, let destination, let additionalChoices, _):
            applyPlay(card: card, destination: destination, additionalChoices: additionalChoices, abilityInstructions: abilityInstructions, to: &state, proposedBy: player)
        case .standardMove(let units, let destination):
            applyStandardMove(units: units, destination: destination, to: &state, proposedBy: player)
        case .draw(let count):
            applyDraw(count: count, to: &state, player: player)
        case .channel(let count, let exhausted):
            applyChannel(count: count, exhausted: exhausted, to: &state, player: player)
        case .recycleRune(let domain):
            applyRecycleRune(domain: domain, to: &state, player: player)
        case .exhaust(let objects):
            applyExhaust(objects: objects, to: &state, player: player)
        case .ready(let objects):
            applyReady(objects: objects, to: &state, player: player)
        case .pass:
            return applyPass(to: &state, player: player)
        case .endTurn:
            // 516.6.b/517.5: ending the Action Phase runs End of Turn and
            // then hands over. The incoming player's Awaken→Draw prefix
            // runs immediately too: 515 grants no window of opportunity
            // between those steps for anyone to act in, so stopping at
            // `.awaken` would just leave the game unable to proceed until
            // something else nudged it.
            let outcome = TurnSequencer.startTurnReporting(TurnSequencer.endTurn(state))
            state = outcome.state
            return outcome.events
        default:
            // TODO: remaining GameAction cases — add here once
            // LegalityValidator gains real logic for them (see
            // LegalityValidator's `.notImplemented` default, which is what
            // currently keeps this branch unreachable from `GameEngine`).
            break
        }
        return []
    }

    /// Rule 558/560–561/563: Playing a Card.
    ///   - 558: remove the card from the Hand.
    ///   - 561: pay its Energy cost from the Rune Pool (already confirmed
    ///     payable by `LegalityValidator.validatePlay`), and its Power cost
    ///     by consuming matching entries from `RunePool.power` (also
    ///     pre-confirmed available/eligible by the validator — see its
    ///     doc comment for what "matching" means).
    ///   - 563.1.c: a Unit enters the Board exhausted (`Unit.init`'s
    ///     default) at the chosen Location, immediately — Units have no
    ///     `ChainItem` shape (see `ChainItem`'s cases), so they resolve
    ///     the moment they're Played regardless of `TurnState`, same as
    ///     always. Whether that's ever actually reachable outside Neutral
    ///     Open (a Unit carrying `Keyword.action`/`.reaction`) is an edge
    ///     case `LegalityValidator.validatePlay`'s keyword check doesn't
    ///     rule out but this Applier doesn't specially handle either —
    ///     flagged, not solved, here.
    ///   - 563.1.d: Gear always enters at the player's Base, Ready,
    ///     regardless of `destination` (144.2 — `LegalityValidator` already
    ///     rejects a Battlefield destination for Gear before this runs).
    ///     Same immediate-resolution note as Units above.
    ///   - 556.2/563.2.b/534: a Spell has no board form and does not
    ///     resolve immediately — `ChainResolver.push` puts it on the Chain
    ///     (opening one if none exists), so Reactions get a real window
    ///     against it (509.1.a) before anything happens. See `.pass`'s
    ///     handling in `apply` for what actually happens once it resolves
    ///     — today, still just "goes to the Trash," since Ability
    ///     execution doesn't exist yet (architecture.md item 7); the
    ///     difference from before is *when* that happens, not *what*.
    private static func applyPlay(
        card cardID: ObjectID,
        destination: PlayDestination,
        additionalChoices: [ObjectID],
        abilityInstructions: [EffectInstruction],
        to state: inout GameState,
        proposedBy player: PlayerID
    ) {
        guard var zones = state.zones[player],
              let index = zones.hand.firstIndex(where: { $0.id == cardID }) else { return }
        let card = zones.hand.remove(at: index)
        zones.runePool.energy = max(0, zones.runePool.energy - card.cost.energy)
        zones.runePool.power = consumingPower(card.cost.powerCost, eligibleDomains: card.cost.eligibleDomains, from: zones.runePool.power)

        switch card.type {
        case .unit(let isChampion):
            let location: Location
            switch destination {
            case .base(let owner): location = .base(owner)
            case .battlefield(let battlefieldID): location = .battlefield(battlefieldID)
            case .none: location = .base(player)  // shouldn't happen — LegalityValidator rejects `.none` for Units
            }
            let unit = Unit(
                owner: player,
                cardDefinitionID: card.definitionID,
                name: card.name,
                isChampion: isChampion,
                baseMight: card.might ?? 0,
                location: location
            )
            state.units[unit.id] = unit

            if case .battlefield(let battlefieldID) = location {
                var control = state.battlefieldControl[battlefieldID] ?? BattlefieldControl()
                if control.controller != player {   // 181.3.a, same as applyStandardMove
                    control.isContested = true
                    control.contestedBy = player
                }
                state.battlefieldControl[battlefieldID] = control
            }

            state.zones[player] = zones
            // 563.1.c: a Unit resolves the moment it's Played — its
            // "when you play me" ability (if any) runs right here, not
            // through the Chain (Units have no ChainItem shape).
            let outcomes = EffectExecutor.run(abilityInstructions, source: unit.id, resolvedTargets: additionalChoices, to: &state, proposedBy: player)
            state.abilityOutcomeSummaries.append(contentsOf: outcomes.map(\.summary))

        case .gear:
            let gear = Gear(owner: player, cardDefinitionID: card.definitionID, name: card.name)
            state.gear[gear.id] = gear
            state.zones[player] = zones

        case .spell:
            state.zones[player] = zones
            // 556.2/563.2.b/534: a Spell has no board form and doesn't
            // resolve immediately — its parsed ability travels with the
            // Chain item (`instructions:`) rather than running now, so a
            // Reaction gets a real window against it (509.1.a) first.
            ChainResolver.push(.spell(card, targets: additionalChoices, instructions: abilityInstructions), proposedBy: player, to: &state)
        }
    }

    /// Rule 540.4/553.4: Pass. Three different things can come of it —
    /// nothing, a Chain item resolving, or a Showdown ending — so this
    /// dispatches on `ChainResolver.PassOutcome` rather than assuming the
    /// middle one.
    ///
    /// The Showdown case is the one that makes a Showdown mean anything:
    /// 553.4.a ends it once everyone has passed in sequence, and 626–628
    /// then resolve the Combat, which is where damage, deaths, Control and
    /// the Conquer score actually happen. `scoringEvents` carries the
    /// resulting `PlayerInstruction`s back out to `GameEngine`.
    private static func applyPass(to state: inout GameState, player: PlayerID) -> [PlayerInstruction] {
        switch ChainResolver.pass(by: player, in: &state) {
        case .recorded:
            return []
        case .resolvedChainItem(let item):
            applyResolvedChainItem(item, to: &state)
            return []
        case .showdownEnded(let showdown):
            let outcome = Combat.resolve(showdown, in: state)
            state = outcome.state
            return outcome.events
        }
    }

    /// Rule 563.2.b: what happens when a Chain item actually resolves.
    /// A Spell goes to its owner's Trash — the same terminal state
    /// `applyPlay` used to assign immediately, before the Chain existed to
    /// delay it through — then executes the ability it carried since Play
    /// (see `ChainItem.spell`'s doc comment), with `source: nil` since a
    /// resolved Spell leaves no board permanent behind to be the source of
    /// its own effect. Activated/Triggered Abilities carry their own
    /// `source`/`proposedBy` already, so they execute the same way.
    private static func applyResolvedChainItem(_ item: ChainItem, to state: inout GameState) {
        switch item {
        case .spell(let card, let targets, let instructions):
            guard var zones = state.zones[card.owner] else { return }
            zones.trash.append(card)
            state.zones[card.owner] = zones
            let outcomes = EffectExecutor.run(instructions, source: nil, resolvedTargets: targets, to: &state, proposedBy: card.owner)
            state.abilityOutcomeSummaries.append(contentsOf: outcomes.map(\.summary))

        case .activatedAbility(let source, _, let proposedBy, let targets, let instructions),
             .triggeredAbility(let source, _, let proposedBy, let targets, let instructions):
            let outcomes = EffectExecutor.run(instructions, source: source, resolvedTargets: targets, to: &state, proposedBy: proposedBy)
            state.abilityOutcomeSummaries.append(contentsOf: outcomes.map(\.summary))
        }
    }

    /// Rule 140: Standard Move.
    ///   - 140.2: exhausting the Unit(s) is the Cost.
    ///   - 610.2/610.3: Moving is defined by Origin/Destination; only Units
    ///     can Move.
    ///   - 181.3.a: moving a Unit controlled by a player who does not
    ///     currently Control the destination Battlefield applies Contested
    ///     status to it (regardless of whether it was Uncontrolled or
    ///     Controlled by someone else).
    ///   - 615: a Cleanup is performed once the Move completes — that is
    ///     the caller's responsibility (`GameEngine.process`), not this
    ///     function's, since Cleanup is a single shared pure function
    ///     (CLAUDE.md point 3) and other action kinds will need to trigger
    ///     it too.
    private static func applyStandardMove(
        units unitIDs: [ObjectID],
        destination: Location,
        to state: inout GameState,
        proposedBy player: PlayerID
    ) {
        for unitID in unitIDs {
            guard var unit = state.units[unitID] else { continue }
            unit.isExhausted = true       // 140.2
            unit.location = destination   // 610.1/610.2
            state.units[unitID] = unit
        }

        guard case .battlefield(let battlefieldID) = destination else { return }

        var control = state.battlefieldControl[battlefieldID] ?? BattlefieldControl()
        if control.controller != player {   // 181.3.a
            control.isContested = true
            control.contestedBy = player
        }
        state.battlefieldControl[battlefieldID] = control
    }

    /// Rule 591: Draw. 591.1: takes the top `count` cards of the player's
    /// Main Deck into their Hand.
    ///
    /// NOTE: 591.4 (drawing more cards than remain in the Main Deck
    /// triggers a Burn Out, rule 607, then continues the draw) is not
    /// handled here — Burn Out doesn't exist yet as an implemented
    /// `GameAction`. For now this just draws as many as are available,
    /// same as 591.4.a alone, and stops; flagging rather than guessing at
    /// 591.4.b/c until Burn Out is built.
    /// Internal rather than private: `EffectExecutor` runs a card's parsed
    /// abilities and must draw through the same path a `.draw` action does,
    /// not a second copy of it.
    static func applyDraw(count: Int, to state: inout GameState, player: PlayerID) {
        guard var zones = state.zones[player] else { return }
        let drawCount = min(count, zones.mainDeck.count)
        zones.hand.append(contentsOf: zones.mainDeck.prefix(drawCount))
        zones.mainDeck.removeFirst(drawCount)
        state.zones[player] = zones

        // Rule 589.2: this draw just fulfilled one authorization — consume
        // it so it can't be reused for a second physical draw.
        if let index = state.pendingLimitedActions[player]?.firstIndex(of: .draw(count: count)) {
            state.pendingLimitedActions[player]?.remove(at: index)
        }
    }

    /// Rule 606.1: Channel — take `count` Runes off the top of the player's
    /// Rune Deck and **put them on the board**, into their Rune Area. They
    /// enter Ready unless the instructing effect said otherwise (606.2).
    ///
    /// This adds no Energy, and that is the whole point. Rule 157.2.a is
    /// `[T]: Add [1]` — a Rune produces Energy when it is *Exhausted*, not
    /// when it is Channeled. The previous version of this function did
    /// `runePool.energy += count`, which handed a player Energy for Runes
    /// they had only placed, let them pay a cost without ever turning a
    /// Rune sideways, and left the physical Rune Area with nothing in it
    /// for the camera to count. See `applyExhaust` for where Energy is
    /// actually produced.
    ///
    /// 515.3.b.1/606: fewer Runes than requested in the deck means channel
    /// as many as possible — not a failure.
    /// Internal for the same reason as `applyDraw`.
    static func applyChannel(count: Int, exhausted: Bool, to state: inout GameState, player: PlayerID) {
        guard var zones = state.zones[player] else { return }
        let channelCount = min(count, zones.runeDeck.count)
        for card in zones.runeDeck.prefix(channelCount) {
            let rune = Rune(owner: player, card: card, isExhausted: exhausted)
            state.runes[rune.id] = rune
        }
        zones.runeDeck.removeFirst(channelCount)
        state.zones[player] = zones
        state.totalRunesChanneled[player, default: 0] += channelCount

        if let index = state.pendingLimitedActions[player]?.firstIndex(of: .channel(count: count, exhausted: exhausted)) {
            state.pendingLimitedActions[player]?.remove(at: index)
        }
    }

    /// Rule 157.2.a (`[T]: Add [1]`): Exhausting a Ready Rune adds 1 Energy
    /// to its controller's Rune Pool. This is the only way Energy is
    /// produced, and it's the physical act the camera can actually see — a
    /// rune rotated sideways in the Rune Area.
    ///
    /// Objects that aren't Runes are exhausted without producing anything
    /// (592: Exhaust is a general Limited Action; only Runes carry 157.2.a's
    /// intrinsic ability). Already-Exhausted Runes produce nothing — the
    /// ability's cost is turning it, and a Rune that's already turned has
    /// nothing left to pay with.
    private static func applyExhaust(objects: [ObjectID], to state: inout GameState, player: PlayerID) {
        for objectID in objects {
            if var rune = state.runes[objectID] {
                guard !rune.isExhausted else { continue }
                rune.isExhausted = true
                state.runes[objectID] = rune
                state.zones[rune.controller]?.runePool.energy += 1   // 157.2.a
            } else if var unit = state.units[objectID] {
                unit.isExhausted = true
                state.units[objectID] = unit
            } else if var gear = state.gear[objectID] {
                gear.isExhausted = true
                state.gear[objectID] = gear
            }
        }
        consumeAuthorization(.exhaust(objects: objects), for: player, in: &state)
    }

    /// Rule 593: Ready — the inverse of Exhaust, and deliberately *not*
    /// symmetric with it: readying a Rune does not remove Energy from the
    /// pool. Energy already added is spent or lost to 160's emptying, never
    /// clawed back by the Rune's stance changing later.
    private static func applyReady(objects: [ObjectID], to state: inout GameState, player: PlayerID) {
        for objectID in objects {
            if var rune = state.runes[objectID] {
                rune.isExhausted = false
                state.runes[objectID] = rune
            } else if var unit = state.units[objectID] {
                unit.isExhausted = false
                state.units[objectID] = unit
            } else if var gear = state.gear[objectID] {
                gear.isExhausted = false
                state.gear[objectID] = gear
            }
        }
        consumeAuthorization(.ready(objects: objects), for: player, in: &state)
    }

    /// Rule 157.2.b (`Recycle this: Add [C]`) + 594.1.b: Recycling a Rune
    /// takes it off the board and puts it on the **bottom of the Rune
    /// Deck** (154.2.b), adding Power of that Rune's Domain to the pool
    /// (157.2.b.1).
    ///
    /// The card really does return to the deck — that's what makes the Rune
    /// Deck able to run out and refill across a long game, and it's why
    /// `Rune` carries its whole `RuneCard` rather than just a Domain.
    /// Previously this only appended to `RunePool.power` and bumped a
    /// counter, which meant recycling was free: the Rune never left the
    /// board, so the same physical Rune could be recycled indefinitely.
    ///
    /// 594.3: a Recycle used as a cost must be completable — the validator
    /// confirms a Rune of this Domain is actually present before this runs.
    /// An Exhausted Rune is as Recyclable as a Ready one (the cost is
    /// returning the card, not turning it), so stance is not consulted;
    /// where both exist, the Exhausted one goes first, since it has already
    /// produced its Energy and is the one with nothing left to give.
    private static func applyRecycleRune(domain: Domain, to state: inout GameState, player: PlayerID) {
        let candidates = state.runes.values.filter { $0.controller == player && $0.domain == domain }
        guard let rune = candidates.first(where: \.isExhausted) ?? candidates.first else { return }

        state.runes[rune.id] = nil
        guard var zones = state.zones[player] else { return }
        zones.runeDeck.append(rune.card)             // 594.1: bottom of the deck
        zones.runePool.power.append(.domain(domain)) // 157.2.b.1
        state.zones[player] = zones
        state.totalRunesRecycled[player, default: 0] += 1

        consumeAuthorization(.recycleRune(domain: domain), for: player, in: &state)
    }

    /// Rule 589.2: an authorization is spent by the action it authorized,
    /// so one "you may draw" can't be redeemed for two physical draws.
    private static func consumeAuthorization(_ action: GameAction, for player: PlayerID, in state: inout GameState) {
        if let index = state.pendingLimitedActions[player]?.firstIndex(of: action) {
            state.pendingLimitedActions[player]?.remove(at: index)
        }
    }

    /// Removes `count` entries from `pool` that are eligible to pay a cost
    /// restricted to `eligibleDomains` — a `.universal` entry always
    /// matches (156.2.b); a `.domain(d)` entry matches iff `d` is in
    /// `eligibleDomains`. Non-matching entries are left untouched
    /// regardless of position. If `pool` has fewer matching entries than
    /// `count` (shouldn't happen — `LegalityValidator` confirms
    /// availability first), removes as many as exist and stops; it does
    /// not go negative or touch non-matching entries to make up the
    /// shortfall.
    private static func consumingPower(_ count: Int, eligibleDomains: [Domain], from pool: [PowerType]) -> [PowerType] {
        guard count > 0 else { return pool }
        var remaining = count
        var result: [PowerType] = []
        result.reserveCapacity(pool.count)
        for entry in pool {
            let isEligible: Bool
            switch entry {
            case .universal: isEligible = true
            case .domain(let d): isEligible = eligibleDomains.contains(d)
            }
            if remaining > 0, isEligible {
                remaining -= 1
            } else {
                result.append(entry)
            }
        }
        return result
    }
}
