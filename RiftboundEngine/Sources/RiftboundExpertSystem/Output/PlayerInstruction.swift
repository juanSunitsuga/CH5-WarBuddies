/// The final pipeline stage: what to tell the human at the table. This is
/// intentionally a small, closed set — resist the temptation to let this
/// grow into a generic string-message type. A fixed vocabulary here is what
/// lets the eventual UI layer render each case with real affordances
/// (highlight a card, show a specific error icon, etc.) instead of just
/// dumping text.
public enum PlayerInstruction: Sendable {
    /// The observed action was legal and has been applied to `GameState`.
    /// Nothing further required of the player for this specific action,
    /// though `followUp` may prompt a required next step (e.g. "assign
    /// combat damage").
    case actionAccepted(GameAction, followUp: FollowUp?)

    /// The observed physical action does not correspond to a legal
    /// `GameAction` in the current state. This is the primary
    /// misplay-catching case — see docs/architecture.md section 5.
    case actionRejected(observed: ObservedTableEvent, reason: LegalityValidator.Failure)

    /// An event didn't map to any proposable action at all (Stage 3
    /// returned nil) — distinct from `actionRejected`, since here there's
    /// no specific rule violation to report, just nothing recognized.
    /// Surfaced at low priority / debug-only in the UI, not as a player-
    /// facing error, to avoid noisy false positives from tracking jitter.
    case unrecognizedEvent(ObservedTableEvent)

    /// The engine needs a choice only a human can make (targeting, damage
    /// assignment, mulligan selection, etc.) — rule 559.3/626.1.d. The UI
    /// layer is responsible for presenting `options` and returning the
    /// choice back into the engine; this case exists so the engine can
    /// pause mid-resolution without blocking on a synchronous callback.
    case choiceRequired(ChoicePrompt)

    /// Rule 632: a player just scored (Conquer or Hold).
    case scored(player: PlayerID, battlefield: BattlefieldID, newTotal: Int)

    case gameWon(player: PlayerID)
}

/// A required next physical step after an accepted action — e.g. "now
/// exhaust these runes to pay the cost" or "combat is starting, resolve
/// attack triggers." Left minimal for now; expand once real card texts
/// make clear what follow-ups actually recur often enough to warrant their
/// own case vs. a generic prompt.
public struct FollowUp: Sendable {
    public let description: String
    public init(description: String) { self.description = description }
}

/// A pending decision the engine is blocked on. `TargetSpec`/damage
/// assignment shapes intentionally reuse `EffectInstruction.TargetSpec`
/// once that's designed (see EffectInstruction.swift) rather than
/// duplicating a parallel targeting vocabulary here.
public struct ChoicePrompt: Sendable {
    public let player: PlayerID
    public let prompt: String
    public let options: [ObjectID]

    public init(player: PlayerID, prompt: String, options: [ObjectID]) {
        self.player = player
        self.prompt = prompt
        self.options = options
    }
}
