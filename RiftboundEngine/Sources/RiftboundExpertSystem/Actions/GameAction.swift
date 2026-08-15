/// Rule 586–589: every action a player (or an effect, on their behalf) can
/// take. Split into Discretionary (player-chosen, gated by Priority — 589.1)
/// and Limited (only performable when a rule or effect explicitly calls
/// for it — 589.2).
///
/// This is the closed vocabulary both the Legality Validator and the
/// OCR-event-inference layer target. See CLAUDE.md point 4: effect
/// resolution must only ever bottom out in these cases — if NLP output
/// can't be mapped onto one of them, that's a parse failure, not a reason
/// to add an ad hoc new case.
public enum GameAction: Sendable, Equatable {
    // MARK: Discretionary (589.1) — a player may choose these at will,
    // subject to Priority, timing state, and costs.

    /// Rule 595: play a card from hand (or another zone, per an effect).
    ///
    /// `observedExhaustedRuneCount`: how many Runes were physically
    /// Exhausted in the player's Rune Area at the moment this Play was
    /// observed, when the proposer has that data — `nil` when it doesn't
    /// (e.g. a manually-constructed action, or a translator with no live
    /// vision access), in which case `LegalityValidator` skips the check
    /// entirely rather than treating "unobserved" as "zero." Rule 130.2:
    /// Energy is paid by Exhausting Runes, so this is the physical
    /// corroboration for `Cost.energy` — same reverse-inference role
    /// `RunePool.power`'s Domain check plays for `Cost.powerCost`, just
    /// not yet backed by a real pool the way Power is (see
    /// `LegalityValidator.Failure.exhaustedRuneCountMismatch`).
    case play(card: ObjectID, destination: PlayDestination, additionalChoices: [ObjectID], observedExhaustedRuneCount: Int? = nil)
    /// Rule 140, 596.3: a Unit's Standard Move — exhaust to move to/from
    /// a Battlefield, or Battlefield-to-Battlefield if Ganking (722).
    case standardMove(units: [ObjectID], destination: Location)
    /// Rule 577: activate a Game Object's Activated Ability.
    case activateAbility(source: ObjectID, effectID: EffectID, targets: [ObjectID])
    /// Rule 597: pay to place a Hidden-keyword card facedown at a
    /// Battlefield the player controls.
    case hide(card: ObjectID, battlefield: BattlefieldID)
    /// Rule 540.4 / 553.4: decline to act at the current priority window.
    case pass
    /// Rule 531.2: invite a non-Relevant player to act instead.
    case invite(player: PlayerID)
    /// Rule 516.6: voluntarily end the Action Phase.
    case endTurn

    // MARK: Limited (589.2) — only ever performed when an effect or a fixed
    // point in the turn structure calls for it; never player-initiated at will.

    case draw(count: Int)
    case exhaust(objects: [ObjectID])
    case ready(objects: [ObjectID])
    case recycle(cards: [ObjectID], to: RecycleDestination)
    /// Rule 130.3: recycle one Rune of `domain` to pay a Power cost. A
    /// domain-only sibling to `.recycle(cards:to:)`, not a replacement for
    /// it — once Channeled, a Rune has no `ObjectID`-tracked board
    /// presence (only `RunePool.power`, an aggregate), so there's no card
    /// identity to name here, only which Domain it was. One rune per case
    /// instance, matching `.channel(count: 1, ...)`'s existing per-observed-
    /// event granularity — paying a multi-symbol Power cost means multiple
    /// `.recycleRune` actions, one per physical Rune recycled, feeding the
    /// same `RunePool.power` that `LegalityValidator` checks against. A
    /// Rune's stance at the moment of Recycling doesn't matter — an
    /// Exhausted Rune is just as Recyclable as a Ready one (only an
    /// unspent Rune is required to still exist at all, which "it's
    /// physically in the Rune Area" already establishes).
    case recycleRune(domain: Domain)
    case discard(cards: [ObjectID])
    case stun(units: [ObjectID])
    case reveal(cards: [ObjectID], from: RevealSource)
    case counter(chainItem: EffectID)
    case buff(units: [ObjectID])
    case banish(objects: [ObjectID])
    case kill(permanents: [ObjectID])
    case add(energy: Int, power: [PowerType])
    case channel(count: Int, exhausted: Bool)
    case burnOut(player: PlayerID)
}

public enum PlayDestination: Sendable, Equatable {
    case base(PlayerID)
    case battlefield(BattlefieldID)
    /// Spells and activated abilities have no board destination.
    case none
}

public enum RecycleDestination: Sendable, Equatable {
    case mainDeck
    case runeDeck
}

public enum RevealSource: Sendable, Equatable {
    case topOfMainDeck(PlayerID, count: Int)
    case hand(PlayerID)
    case other(String)
}
