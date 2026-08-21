/// The orchestrator that wires together the full pipeline described in
/// chat:
///
///   Table (Open Hands / opponent cards visible)
///     → OCR + Mapping                    → CardIdentification        [Ingestion/CardIdentification.swift]
///     → Object Tracking                  → ObservedTableEvent        [Ingestion/ObservedTableEvent.swift]
///     → NLP translation                  → candidate GameAction      [Ingestion/ActionTranslating.swift]
///     → LegalityValidator + GameStateStore → validated state change  [Validation/, StateMachine/]
///     → PlayerInstruction                → what to tell the human    [Output/PlayerInstruction.swift]
///
/// This type owns no game logic itself — it's purely plumbing between the
/// pieces that already exist. Keeping it this thin is deliberate: if
/// `GameEngine` starts accumulating rule logic instead of delegating to
/// `LegalityValidator`/`Cleanup`/effect execution, that logic has ended up
/// in the wrong place.
public actor GameEngine {
    private let store: GameStateStore
    private let observer: any BoardObserving
    private let translator: any ActionTranslating
    private let informationMode: InformationMode

    public init(
        store: GameStateStore,
        observer: any BoardObserving,
        translator: any ActionTranslating,
        informationMode: InformationMode = .openHands
    ) {
        self.store = store
        self.observer = observer
        self.translator = translator
        self.informationMode = informationMode
    }

    /// Runs the pipeline continuously, yielding a `PlayerInstruction` for
    /// every observed table event. Callers (the SwiftUI shell) consume
    /// this to drive on-screen feedback.
    public func run() -> AsyncStream<PlayerInstruction> {
        AsyncStream { continuation in
            Task {
                for await event in observer.events() {
                    let instruction = await self.process(event)
                    continuation.yield(instruction)
                }
                continuation.finish()
            }
        }
    }

    /// The per-event pipeline, exposed directly (not just via `run()`) so
    /// tests can feed a single `ObservedTableEvent` and assert on the
    /// resulting `PlayerInstruction` without needing a running observer —
    /// this is the seam CLAUDE.md's testing guidance is talking about.
    public func process(_ event: ObservedTableEvent) async -> PlayerInstruction {
        let snapshot = await store.currentState

        guard let proposer = proposingPlayer(for: event) else {
            // Couldn't attribute the event to a player at all (e.g. no
            // region info survived tracking) — nothing downstream can
            // meaningfully validate this.
            return .unrecognizedEvent(event)
        }

        guard let candidateAction = await translator.inferAction(
            from: event, in: snapshot, proposedBy: proposer
        ) else {
            return .unrecognizedEvent(event)
        }

        switch LegalityValidator.validate(candidateAction, in: snapshot, proposedBy: proposer) {
        case .failure(let reason):
            return .actionRejected(observed: event, reason: reason)

        case .success:
            // A played card's own text resolves as part of playing it, so
            // its instructions have to be in hand *before* the mutation —
            // `store.mutate` is synchronous and the lookup is async. Read
            // from the pre-play snapshot, where the card is still in hand.
            let effects = await abilities(triggeredBy: candidateAction, in: snapshot, player: proposer)

            // 615/519: apply the action, run the card's own effects, then
            // Cleanup — all as one atomic transform through the store
            // (CLAUDE.md point 2/3). Cleanup runs once at the end rather
            // than after each effect, so nothing observes a half-resolved
            // card.
            let consequences = ConsequenceBox()
            _ = await store.mutate { state in
                consequences.events = GameActionApplier.apply(candidateAction, to: &state, proposedBy: proposer)
                consequences.effects = EffectExecutor.run(effects, on: &state, player: proposer)
                state = Cleanup.run(state)
            }

            // 632/633: an action can *cause* something the player needs
            // told that isn't the action itself — a Conquer, a Hold, a win.
            // Those outrank the bare acknowledgement: "you won the game"
            // must not be reported as "move accepted."
            if let win = consequences.events.first(where: { if case .gameWon = $0 { return true } else { return false } }) {
                return win
            }
            if let scored = consequences.events.first(where: { if case .scored = $0 { return true } else { return false } }) {
                return scored
            }
            return .actionAccepted(candidateAction, followUp: followUp(for: consequences.effects))
        }
    }

    /// The played card's own instructions, if this action put one on the
    /// board.
    ///
    /// Only `.play` — a Move or a Draw doesn't re-trigger a card's text.
    /// Looked up by the card's definition, so the translator can cache per
    /// definition rather than per copy.
    private func abilities(
        triggeredBy action: GameAction,
        in snapshot: GameState,
        player: PlayerID
    ) async -> [EffectInstruction] {
        guard case .play(let cardID, _, _, _) = action,
              let card = snapshot.zones[player]?.hand.first(where: { $0.id == cardID })
        else { return [] }
        return await translator.abilities(of: card.definitionID)
    }

    /// Turns what the effects did into one line for the player.
    ///
    /// Both halves matter and they're phrased differently on purpose. What
    /// the engine applied is reported in the past tense, because it has
    /// already happened and the player is being told, not asked. What it
    /// deferred is an instruction, because the board is not finished until
    /// the player does it.
    private func followUp(for outcome: EffectExecutor.Outcome) -> FollowUp? {
        guard !outcome.isEmpty else { return nil }

        var parts: [String] = []
        if !outcome.applied.isEmpty {
            parts.append("I've applied: " + outcome.applied.map(\.playerFacingSummary).joined(separator: " "))
        }
        parts.append(contentsOf: outcome.deferred)
        return FollowUp(description: parts.joined(separator: " "))
    }

    /// Carries the applier's events out of the `store.mutate` closure.
    /// `mutate` yields only the new `GameState`, and these events are
    /// deliberately *not* on `GameState` — they're a record of what just
    /// happened, not part of the game's state, and putting them there would
    /// mean every snapshot carried a growing log of past events.
    private final class ConsequenceBox: @unchecked Sendable {
        var events: [PlayerInstruction] = []
        var effects = EffectExecutor.Outcome()
    }

    /// Attribution: whose action this physically was, derived from which
    /// player's table region the event occurred in. NOT the same as "whose
    /// turn it is" — a Reaction can legally be played on someone else's
    /// turn (rule 725), so conflating the two here would make the
    /// validator reject legal Reactions outright. Region ownership is
    /// ground truth for *who touched a card*; whether that's currently
    /// legal is `LegalityValidator`'s job downstream, not this function's.
    private func proposingPlayer(for event: ObservedTableEvent) -> PlayerID? {
        switch event.kind {
        case .cardAppeared(let region), .cardRemoved(let region), .cardOrientationChanged(let region, _):
            return region.owner
        case .cardMoved(let from, _):
            return from.owner
        }
    }
}
