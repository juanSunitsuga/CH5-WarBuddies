/// The structured output the NLP layer should produce from parsing a card's
/// rules text. Each case maps onto exactly one `GameAction` (or a small
/// fixed sequence of them) — this enum exists as the *target vocabulary*
/// for parsing, separate from `GameAction` itself, because a single parsed
/// instruction may need to resolve conditionally (e.g. targeting,
/// mistargeting per rule 559.3.c) before it's known which `GameAction`(s)
/// it actually produces.
///
/// TargetSpec/LocationSpec are intentionally left unimplemented here — they
/// need to describe *selection criteria* ("a unit at a battlefield",
/// "friendly units", "an enemy unit with Tank") for the Validator to check
/// legality against current GameState at resolution time (rule 563.2.c),
/// not just at declaration time. Design these once a batch of real card
/// texts is available to pressure-test the vocabulary against — don't
/// guess the shape prematurely.
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

    /// TODO — placeholder; not yet designed. See doc comment above.
    public enum TargetSpec: Sendable { case placeholder }
    /// TODO — placeholder; not yet designed.
    public enum LocationSpec: Sendable { case placeholder }
    /// TODO — e.g. Legion's "have you played another Main Deck card this
    /// turn" (724), or Might/keyword checks. Needs a small expression
    /// language once real card texts are in hand.
    public enum EffectCondition: Sendable { case placeholder }
}
