/// Runs a parsed card ability's `[EffectInstruction]`s against `GameState`
/// — the counterpart to `GameActionApplier` for the effects vocabulary
/// rather than the action vocabulary. Same purity contract: mutates
/// `state` in place, produces no side effects of its own, and must only
/// ever run inside `GameStateStore.mutate` (CLAUDE.md point 2).
///
/// Not every `EffectInstruction` case executes yet — `TargetSpec`/
/// `LocationSpec` were pressure-tested against a real card-text sample,
/// and several cases (`.counterSpell`, `.recycleCard`, `.revealCards`,
/// `.moveUnit`, `.addResources`, `.conditional`) have no producer in that
/// sample yet either. Those report themselves as not-yet-executed in the
/// returned summary rather than guessing at behavior nothing has pressure
/// tested — CLAUDE.md point 4.
public enum EffectExecutor {
    /// One resolved outcome, for the caller to fold into a `FollowUp`
    /// description — this layer doesn't decide how effect results reach
    /// the player, only what happened.
    public struct Outcome: Sendable {
        public let summary: String
        public let executed: Bool
    }

    /// - Parameters:
    ///   - instructions: the ability's parsed effects, in resolution order.
    ///   - source: the permanent whose ability this is — what `.source`
    ///     targeting resolves to. `nil` for a Spell, which has no lasting
    ///     board permanent to be the source of its own effect.
    ///   - resolvedTargets: `GameAction.play`'s `additionalChoices` —
    ///     already-declared target `ObjectID`s (559.3), consumed in order,
    ///     one per `TargetSpec` that needs one (`.chosenUnit` takes one,
    ///     `.upToUnits(maximum:)` takes up to `maximum`).
    @discardableResult
    public static func run(
        _ instructions: [EffectInstruction],
        source: ObjectID?,
        resolvedTargets: [ObjectID],
        to state: inout GameState,
        proposedBy player: PlayerID
    ) -> [Outcome] {
        var remainingTargets = resolvedTargets[...]
        return instructions.map { execute($0, source: source, remainingTargets: &remainingTargets, to: &state, proposedBy: player) }
    }

    private static func execute(
        _ instruction: EffectInstruction,
        source: ObjectID?,
        remainingTargets: inout ArraySlice<ObjectID>,
        to state: inout GameState,
        proposedBy player: PlayerID
    ) -> Outcome {
        switch instruction {
        case .dealDamage(let amount, let targets):
            let units = resolve(targets, source: source, remainingTargets: &remainingTargets, in: state, proposedBy: player)
            guard !units.isEmpty else {
                return Outcome(summary: "Dealt \(amount) damage — no resolvable target.", executed: false)
            }
            for unitID in units {
                state.units[unitID]?.damage += amount
            }
            return Outcome(summary: "Dealt \(amount) damage to \(units.count) unit\(units.count == 1 ? "" : "s").", executed: true)

        case .draw(let count):
            guard var zones = state.zones[player] else {
                return Outcome(summary: "Draw \(count) — no zones for \(player).", executed: false)
            }
            let drawCount = min(count, zones.mainDeck.count)
            zones.hand.append(contentsOf: zones.mainDeck.prefix(drawCount))
            zones.mainDeck.removeFirst(drawCount)
            state.zones[player] = zones
            return Outcome(summary: "Drew \(drawCount) card\(drawCount == 1 ? "" : "s").", executed: true)

        case .discard(let count):
            guard var zones = state.zones[player] else {
                return Outcome(summary: "Discard \(count) — no zones for \(player).", executed: false)
            }
            // Rule 559.3 would have the player choose which cards — this
            // vocabulary doesn't yet carry per-card discard choices (no
            // sample card needed one), so this discards from the end of
            // Hand deterministically rather than blocking on a choice
            // nothing upstream can supply yet.
            let discardCount = min(count, zones.hand.count)
            let discarded = zones.hand.suffix(discardCount)
            zones.hand.removeLast(discardCount)
            zones.trash.append(contentsOf: discarded.map { $0 as any Card })
            state.zones[player] = zones
            return Outcome(summary: "Discarded \(discardCount) card\(discardCount == 1 ? "" : "s").", executed: true)

        case .buff(let targets):
            let units = resolve(targets, source: source, remainingTargets: &remainingTargets, in: state, proposedBy: player)
            guard !units.isEmpty else {
                return Outcome(summary: "Buff — no resolvable target.", executed: false)
            }
            for unitID in units {
                state.units[unitID]?.hasBuff = true  // 701–705: one buff slot, not a stacking amount.
            }
            return Outcome(summary: "Buffed \(units.count) unit\(units.count == 1 ? "" : "s").", executed: true)

        case .channelRune(let count, let exhausted):
            guard var zones = state.zones[player] else {
                return Outcome(summary: "Channel \(count) — no zones for \(player).", executed: false)
            }
            let channelCount = min(count, zones.runeDeck.count)
            for card in zones.runeDeck.prefix(channelCount) {
                state.runes[Rune(owner: player, card: card, isExhausted: exhausted).id] = Rune(owner: player, card: card, isExhausted: exhausted)
            }
            zones.runeDeck.removeFirst(channelCount)
            state.zones[player] = zones
            state.totalRunesChanneled[player, default: 0] += channelCount
            return Outcome(summary: "Channeled \(channelCount) rune\(channelCount == 1 ? "" : "s").", executed: true)

        case .killUnit(let targets):
            let units = resolve(targets, source: source, remainingTargets: &remainingTargets, in: state, proposedBy: player)
            guard !units.isEmpty else {
                return Outcome(summary: "Kill — no resolvable target.", executed: false)
            }
            for unitID in units {
                // 139: a killed Unit leaves the board. It should end up in
                // its owner's Trash — not modeled here because `Unit`
                // (the board instance) doesn't retain the `MainDeckCard`
                // it was played from, so there's no card to append.
                // Flagged, not guessed: the board state is correct
                // (the unit is gone), the Trash bookkeeping is the gap.
                state.units[unitID] = nil
            }
            return Outcome(summary: "Killed \(units.count) unit\(units.count == 1 ? "" : "s").", executed: true)

        case .banishCard(let targets):
            let units = resolve(targets, source: source, remainingTargets: &remainingTargets, in: state, proposedBy: player)
            guard !units.isEmpty else {
                return Outcome(summary: "Banish — no resolvable target.", executed: false)
            }
            for unitID in units {
                state.units[unitID] = nil  // Same board-state caveat as killUnit.
            }
            return Outcome(summary: "Banished \(units.count) unit\(units.count == 1 ? "" : "s").", executed: true)

        case .readyObject(let targets):
            let units = resolve(targets, source: source, remainingTargets: &remainingTargets, in: state, proposedBy: player)
            guard !units.isEmpty else {
                return Outcome(summary: "Ready — no resolvable target.", executed: false)
            }
            for unitID in units {
                state.units[unitID]?.isExhausted = false
            }
            return Outcome(summary: "Readied \(units.count) unit\(units.count == 1 ? "" : "s").", executed: true)

        case .exhaustObject(let targets):
            let units = resolve(targets, source: source, remainingTargets: &remainingTargets, in: state, proposedBy: player)
            guard !units.isEmpty else {
                return Outcome(summary: "Exhaust — no resolvable target.", executed: false)
            }
            for unitID in units {
                state.units[unitID]?.isExhausted = true
            }
            return Outcome(summary: "Exhausted \(units.count) unit\(units.count == 1 ? "" : "s").", executed: true)

        case .stunUnit, .counterSpell, .recycleCard, .revealCards, .moveUnit, .addResources, .conditional:
            return Outcome(summary: "\(describe(instruction)) — not yet executed.", executed: false)
        }
    }

    /// `TargetSpec` → the `Unit`s it actually reaches right now.
    /// "friendly"/"enemy" (`UnitFilter`) is relative to `player` — the
    /// ability's proposer, i.e. whoever controls the source permanent —
    /// not to any per-target frame of reference.
    private static func resolve(
        _ spec: EffectInstruction.TargetSpec,
        source: ObjectID?,
        remainingTargets: inout ArraySlice<ObjectID>,
        in state: GameState,
        proposedBy player: PlayerID
    ) -> [ObjectID] {
        switch spec {
        case .source:
            guard let source, state.units[source] != nil else { return [] }
            return [source]

        case .chosenUnit(let filter):
            guard let next = remainingTargets.popFirst(), matches(next, filter: filter, in: state, proposedBy: player) else { return [] }
            return [next]

        case .upToUnits(let maximum, let filter):
            var picked: [ObjectID] = []
            while picked.count < maximum, let next = remainingTargets.first {
                remainingTargets.removeFirst()
                if matches(next, filter: filter, in: state, proposedBy: player) { picked.append(next) }
            }
            return picked

        case .allUnits(let filter):
            return state.units.values
                .filter { unitMatches($0, filter: filter, proposedBy: player) }
                .map(\.id)

        case .unresolved:
            return []
        }
    }

    private static func matches(_ unitID: ObjectID, filter: EffectInstruction.UnitFilter, in state: GameState, proposedBy player: PlayerID) -> Bool {
        guard let unit = state.units[unitID] else { return false }
        return unitMatches(unit, filter: filter, proposedBy: player)
    }

    private static func unitMatches(_ unit: Unit, filter: EffectInstruction.UnitFilter, proposedBy player: PlayerID) -> Bool {
        switch filter {
        case .any: return true
        case .friendly: return unit.controller == player
        case .enemy: return unit.controller != player
        }
    }

    private static func describe(_ instruction: EffectInstruction) -> String {
        switch instruction {
        case .stunUnit: return "Stun"
        case .counterSpell: return "Counter"
        case .recycleCard: return "Recycle"
        case .revealCards: return "Reveal"
        case .moveUnit: return "Move"
        case .addResources: return "Add resources"
        case .conditional: return "Conditional effect"
        default: return "Effect"
        }
    }
}
