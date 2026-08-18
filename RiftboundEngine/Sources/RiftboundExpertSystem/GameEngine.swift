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
            // 615/519: apply the action, then Cleanup — both must run as
            // one atomic transform through the store (CLAUDE.md point 2/3).
            let consequences = ConsequenceBox()
            _ = await store.mutate { state in
                consequences.events = GameActionApplier.apply(candidateAction, to: &state, proposedBy: proposer)
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
            return .actionAccepted(candidateAction, followUp: nil)
        }
    }

    /// Carries the applier's events out of the `store.mutate` closure.
    /// `mutate` yields only the new `GameState`, and these events are
    /// deliberately *not* on `GameState` — they're a record of what just
    /// happened, not part of the game's state, and putting them there would
    /// mean every snapshot carried a growing log of past events.
    private final class ConsequenceBox: @unchecked Sendable {
        var events: [PlayerInstruction] = []
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
