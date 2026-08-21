/// The structured output the NLP layer should produce from parsing a card's
/// rules text. Each case maps onto exactly one `GameAction` (or a small
/// fixed sequence of them) — this enum exists as the *target vocabulary*
/// for parsing, separate from `GameAction` itself, because a single parsed
/// instruction may need to resolve conditionally (e.g. targeting,
/// mistargeting per rule 559.3.c) before it's known which `GameAction`(s)
/// it actually produces.
public enum EffectInstruction: Sendable {
    case dealDamage(amount: Int, targets: TargetSpec)
    case draw(count: Int)
    case discard(count: Int)
    case buff(targets: TargetSpec)
    case moveUnit(unit: TargetSpec, destination: LocationSpec)
    case channelRune(count: Int, exhausted: Bool)
    case killUnit(targets: TargetSpec)
    case stunUnit(targets: TargetSpec)
    case counterSpell(targets: TargetSpec)
    case readyObject(targets: TargetSpec)
    case exhaustObject(targets: TargetSpec)
    case recycleCard(targets: TargetSpec, destination: RecycleDestination)
    case revealCards(source: RevealSource)
    case banishCard(targets: TargetSpec)
    case addResources(energy: Int, power: [PowerType])
    case conditional(condition: EffectCondition, then: [EffectInstruction], else_: [EffectInstruction] = [])

    /// Who/what an effect reaches — pressure-tested against a ~75-card
    /// sample of real printed text rather than designed in the abstract.
    /// Deliberately small: it covers the selection shapes that sample
    /// actually uses, not every shape Riftbound's full text could
    /// eventually need.
    public enum TargetSpec: Sendable, Equatable {
        /// The permanent that generated this effect — "give me +1 Might."
        case source
        /// A single object the proposer already chose when declaring the
        /// action (559.3) — carried on `GameAction.play`'s
        /// `additionalChoices`, one entry per `TargetSpec` that needs one,
        /// in declaration order. This only narrows *which* controller the
        /// choice must belong to; it does not pick one itself.
        case chosenUnit(UnitFilter = .any)
        /// "each enemy unit", "all units at a battlefield" — every unit
        /// currently matching `filter`, resolved at execution time with no
        /// player choice involved.
        case allUnits(UnitFilter = .any)
        /// "up to two units" — a player-chosen subset, bounded above by
        /// `maximum`. Same `additionalChoices` mechanism as `chosenUnit`,
        /// just multiple entries instead of one.
        case upToUnits(maximum: Int, filter: UnitFilter = .any)
        /// A target shape this vocabulary doesn't cover yet — carried
        /// through rather than dropped, so a caller can still tell the
        /// player what the card claims to do even though nothing resolves
        /// it automatically.
        case unresolved
    }

    /// Which controller's units a `TargetSpec` may select from.
    public enum UnitFilter: Sendable, Equatable {
        case any
        case friendly
        case enemy
    }

    /// Where a moved/recycled card ends up — controller-relative, same
    /// framing `RecycleDestination`/`PlayDestination` already use
    /// elsewhere in this module, rather than inventing a second one.
    public enum LocationSpec: Sendable, Equatable {
        case ownBase
        case battlefield
        case ownHand
        case ownTrash
        case unresolved
    }

    /// TODO — e.g. Legion's "have you played another Main Deck card this
    /// turn" (724), or Might/keyword checks. Needs a small expression
    /// language once real card texts are in hand; none of this
    /// vocabulary's current producers emit `.conditional` yet, so this
    /// stays a placeholder until one does.
    public enum EffectCondition: Sendable { case placeholder }
}
