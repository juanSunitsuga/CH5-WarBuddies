/// The contract for Stage 3 (NLP translation). Two distinct jobs live
/// behind this one protocol, since both are "turn observation into
/// something the engine understands" but at different moments:
///
///   1. **Action inference**: given an `ObservedTableEvent` plus current
///      `GameState`, decide which candidate `GameAction` it most plausibly
///      represents (a card moving Base → Battlefield during the Turn
///      Player's Action Phase is very likely a Standard Move; the same
///      movement mid-Chain-resolution is very likely the visible effect of
///      something already on the Chain, not a new player-initiated action).
///      This does NOT decide legality — that's still `LegalityValidator`'s
///      job. This only decides *intent*.
///
///   2. **Ability parsing**: given a card's printed rules text (looked up
///      by `CardDefID`, once your text corpus exists), produce the
///      `[EffectInstruction]` sequence that card's ability represents. This
///      can happen once per unique card definition and be cached — it does
///      not need re-running per game.
///
/// Keeping these on one protocol (rather than splitting NLP into two
/// separate subsystems) reflects that they're both "text/observation to
/// structured engine input," even though their *inputs* differ. Revisit
/// this if the two ever need genuinely different infra (e.g. ability
/// parsing runs offline/pre-computed while action inference must be
/// real-time) — that's a plausible enough outcome that this protocol
/// shouldn't be assumed permanent.
public protocol ActionTranslating: Sendable {
    /// Stage 3a: observation → candidate action. Returns nil if the event
    /// doesn't correspond to any legal-vocabulary `GameAction` (e.g. noise,
    /// or a move that's just an effect's visible side-effect rather than a
    /// player-initiated action) — the caller should not surface a validator
    /// error for a nil result, since "not a proposable action" and
    /// "proposed but illegal" are different outcomes for the Instruction
    /// layer to communicate differently.
    func inferAction(
        from event: ObservedTableEvent,
        in state: GameState,
        proposedBy player: PlayerID
    ) async -> GameAction?

    /// Stage 3b: card text → structured effect. `rawText` is the printed
    /// rules text (534.2 Rules Text); returns the closed-vocabulary
    /// instructions per CLAUDE.md point 4. Should be pure/deterministic
    /// for a given `rawText` so callers can cache by `CardDefID`.
    func parseAbility(rawText: String, cardDefinitionID: CardDefID) async -> [EffectInstruction]
}
