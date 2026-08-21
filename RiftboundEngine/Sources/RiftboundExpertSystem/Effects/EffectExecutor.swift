/// Runs a card's parsed abilities against `GameState` — the first half of
/// architecture item 7b.
///
/// **It runs only what it can run correctly, and says the rest out loud.**
/// That split is the whole design. `EffectInstruction`'s `TargetSpec`,
/// `LocationSpec` and `EffectCondition` are still `.placeholder` on purpose
/// (their shape is being settled against real card text), so an instruction
/// carrying one cannot be aimed. Applying it anyway would mean choosing a
/// target on the player's behalf — inventing a game state nobody can trace
/// back to a decision, which CLAUDE.md point 4 exists to prevent. Those
/// come back as `deferred` sentences instead, for the player to resolve at
/// the table.
///
/// So a card's text now reaches `GameState` where the instruction is
/// unambiguous, and reaches the *player* where it isn't. Neither half
/// guesses.
public enum EffectExecutor {

    /// What running a card's abilities actually did.
    public struct Outcome: Sendable, Equatable {
        /// Applied to `GameState`, in order.
        public var applied: [EffectInstruction]
        /// Needs a person: a target to choose, a condition to judge, or a
        /// card to pick. One player-readable sentence each.
        public var deferred: [String]

        public var isEmpty: Bool { applied.isEmpty && deferred.isEmpty }

        public init(applied: [EffectInstruction] = [], deferred: [String] = []) {
            self.applied = applied
            self.deferred = deferred
        }
    }

    /// Applies what it can and reports what it can't.
    ///
    /// The caller is responsible for running `Cleanup` afterwards, inside
    /// the same `store.mutate` — see CLAUDE.md point 3. This function
    /// deliberately doesn't call it, so a caller can run several effects
    /// and Cleanup once rather than interleaving them.
    public static func run(
        _ instructions: [EffectInstruction],
        on state: inout GameState,
        player: PlayerID
    ) -> Outcome {
        var outcome = Outcome()

        for instruction in instructions {
            switch instruction {

            // MARK: - Unambiguous: a count, and no choice to make

            case .draw(let count) where count > 0:
                // 594.1: the drawing player is the one resolving the
                // ability, which for a card just played is its controller.
                GameActionApplier.applyDraw(count: count, to: &state, player: player)
                outcome.applied.append(instruction)

            case .channelRune(let count, let exhausted) where count > 0:
                GameActionApplier.applyChannel(count: count, exhausted: exhausted, to: &state, player: player)
                outcome.applied.append(instruction)

            case .addResources(let energy, let power) where energy > 0 || !power.isEmpty:
                // 157.2.a: Add is the one effect that puts Energy in a pool
                // without anything being chosen.
                state.zones[player]?.runePool.energy += energy
                state.zones[player]?.runePool.power.append(contentsOf: power)
                outcome.applied.append(instruction)

            // MARK: - Needs a person

            // Which card leaves the hand is the player's choice (594.3);
            // "discard 2" doesn't say which 2. A count is not a target.
            case .discard(let count):
                outcome.deferred.append("Discard \(count) card\(count == 1 ? "" : "s").")

            case .dealDamage(let amount, _):
                outcome.deferred.append("Deal \(amount) damage — choose what it hits.")
            case .killUnit:
                outcome.deferred.append("Kill a unit — choose which.")
            case .stunUnit:
                outcome.deferred.append("Stun a unit — choose which.")
            case .counterSpell:
                outcome.deferred.append("Counter a spell — choose which.")
            case .banishCard:
                outcome.deferred.append("Banish a card — choose which.")
            case .buff:
                outcome.deferred.append("Give a unit a buff — choose which.")
            case .readyObject:
                outcome.deferred.append("Ready a card — choose which, and turn it upright.")
            case .exhaustObject:
                outcome.deferred.append("Exhaust a card — choose which, and turn it sideways.")
            case .moveUnit:
                outcome.deferred.append("Move a unit — choose which, and where to.")
            case .recycleCard(_, let destination):
                outcome.deferred.append("Recycle a card to the bottom of your \(destination.playerFacingName) — choose which.")
            case .revealCards:
                outcome.deferred.append("Reveal the cards this names, then carry on.")
            case .conditional:
                // The condition itself is a placeholder, so the engine
                // cannot even tell which branch applies.
                outcome.deferred.append("This card's ability depends on a condition — check it and resolve it yourself.")

            // MARK: - Degenerate counts

            // A parse that produced "draw 0" is a parser bug, not an
            // effect. Saying so beats silently doing nothing.
            case .draw, .channelRune, .addResources:
                outcome.deferred.append("This card's ability didn't read as a number I could act on — resolve it yourself.")
            }
        }

        return outcome
    }
}

extension RecycleDestination {
    /// The deck a player would actually look for.
    var playerFacingName: String {
        switch self {
        case .mainDeck: return "main deck"
        case .runeDeck: return "rune deck"
        }
    }
}

public extension EffectInstruction {
    /// What an *applied* effect did, in the past tense, for the player.
    ///
    /// Only the executable cases get a real sentence — everything else is
    /// reported through `EffectExecutor.Outcome.deferred`, which phrases it
    /// as an instruction instead. A case reaching the fallback here means
    /// the executor applied something this hasn't been taught to describe,
    /// so it says so rather than staying silent about a state change.
    var playerFacingSummary: String {
        switch self {
        case .draw(let count):
            return "drew \(count) card\(count == 1 ? "" : "s")."
        case .channelRune(let count, let exhausted):
            return "channeled \(count) rune\(count == 1 ? "" : "s")\(exhausted ? ", sideways" : "")."
        case .addResources(let energy, let power):
            var bits: [String] = []
            if energy > 0 { bits.append("\(energy) Energy") }
            if !power.isEmpty { bits.append("\(power.count) Power") }
            return "added \(bits.joined(separator: " and "))."
        default:
            return "resolved part of this card — check the board."
        }
    }
}
