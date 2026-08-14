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
    public static func apply(_ action: GameAction, to state: inout GameState, proposedBy player: PlayerID) {
        switch action {
        case .play(let card, let destination, let additionalChoices, _):
            applyPlay(card: card, destination: destination, additionalChoices: additionalChoices, to: &state, proposedBy: player)
        case .standardMove(let units, let destination):
            applyStandardMove(units: units, destination: destination, to: &state, proposedBy: player)
        case .draw(let count):
            applyDraw(count: count, to: &state, player: player)
        case .channel(let count, _):
            applyChannel(count: count, to: &state, player: player)
        case .recycleRune(let domain):
            applyRecycleRune(domain: domain, to: &state, player: player)
        default:
            // TODO: remaining GameAction cases — add here once
            // LegalityValidator gains real logic for them (see
            // LegalityValidator's `.notImplemented` default, which is what
            // currently keeps this branch unreachable from `GameEngine`).
            break
        }
    }

    /// Rule 558/560–561/563: Playing a Card, simplified to resolve
    /// immediately rather than passing through the Chain's open/close cycle
    /// and Reaction pass-around (563.2.a) — CLAUDE.md point 5 flags the
    /// Chain as load-bearing for real Reaction/Legion timing, but a live
    /// single-mat demo with `LegalityValidator` restricted to Neutral Open
    /// has no second player to pass priority to yet, so there's no
    /// observable difference today. Revisit once the Chain is actually
    /// driven by this pipeline instead of only unit-tested in isolation.
    ///   - 558: remove the card from the Hand.
    ///   - 561: pay its Energy cost from the Rune Pool (already confirmed
    ///     payable by `LegalityValidator.validatePlay`), and its Power cost
    ///     by consuming matching entries from `RunePool.power` (also
    ///     pre-confirmed available/eligible by the validator — see its
    ///     doc comment for what "matching" means).
    ///   - 563.1.c: a Unit enters the Board exhausted (`Unit.init`'s
    ///     default) at the chosen Location.
    ///   - 563.1.d: Gear always enters at the player's Base, Ready,
    ///     regardless of `destination` (144.2 — `LegalityValidator` already
    ///     rejects a Battlefield destination for Gear before this runs).
    ///   - 556.2/563.2.b: a Spell has no board form. Ability resolution
    ///     isn't implemented yet (`parseAbility` always returns `[]`), so
    ///     this moves it straight to the Trash rather than executing an
    ///     effect that doesn't exist — flagged, not guessed at.
    private static func applyPlay(
        card cardID: ObjectID,
        destination: PlayDestination,
        additionalChoices: [ObjectID],
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

        case .gear:
            let gear = Gear(owner: player, cardDefinitionID: card.definitionID, name: card.name)
            state.gear[gear.id] = gear

        case .spell:
            zones.trash.append(card)
        }

        state.zones[player] = zones
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
    private static func applyDraw(count: Int, to state: inout GameState, player: PlayerID) {
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

    /// Rule 154.3: Channel — move `count` Runes from the Rune Deck into
    /// the Rune Pool as Energy. Individual Runes aren't tracked as board
    /// objects (see `GameAction.recycleRune`'s doc comment), so this only
    /// touches the aggregate `RunePool.energy` plus the cumulative
    /// `totalRunesChanneled` tally `GameState` keeps for the pace check —
    /// it does not remove cards from `zones.runeDeck` one-for-one, since
    /// there's no per-Rune identity here to remove. Deliberately NOT
    /// domain-typed, unlike `applyRecycleRune` — Energy is paid by
    /// exhausting Runes regardless of Domain (130.2), so which Domain got
    /// Channeled doesn't matter for anything Energy touches.
    private static func applyChannel(count: Int, to state: inout GameState, player: PlayerID) {
        guard var zones = state.zones[player] else { return }
        zones.runePool.energy += count
        state.zones[player] = zones
        state.totalRunesChanneled[player, default: 0] += count

        if let index = state.pendingLimitedActions[player]?.firstIndex(of: .channel(count: count, exhausted: false)) {
            state.pendingLimitedActions[player]?.remove(at: index)
        }
    }

    /// Rule 130.3: Recycle one Rune of `domain` to pay a Power cost — adds
    /// it to the spendable `RunePool.power` pool (which `applyPlay`
    /// consumes from and `LegalityValidator.validatePlay` checks against)
    /// and separately records the recycle against the cumulative
    /// `totalRunesRecycled` tally, so `totalRunesChanneled -
    /// totalRunesRecycled` stays the correct "should still be visible in
    /// the Rune Area" figure for the vision layer's live count to
    /// reconcile against. These two effects are independent — the pool
    /// entry gets consumed by a later Play, but the recycle still
    /// happened, so the cumulative tally does not reverse.
    private static func applyRecycleRune(domain: Domain, to state: inout GameState, player: PlayerID) {
        guard var zones = state.zones[player] else { return }
        zones.runePool.power.append(.domain(domain))
        state.zones[player] = zones
        state.totalRunesRecycled[player, default: 0] += 1

        if let index = state.pendingLimitedActions[player]?.firstIndex(of: .recycleRune(domain: domain)) {
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
