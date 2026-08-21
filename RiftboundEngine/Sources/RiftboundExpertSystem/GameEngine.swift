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

        return await runValidated(candidateAction, in: snapshot, proposedBy: proposer, fallbackEvent: event)
    }

    /// The landing event `process(_:)` would otherwise have run — held
    /// back and resubmitted once the caller has watched a Play's payment
    /// settle. `observedExhaustedRuneCount` is only known at that point
    /// (`RiftboundVision.PendingPlay` watches Energy/Power get paid over
    /// several frames *after* the card lands), well after the moment
    /// `process(_:)` would normally fire.
    ///
    /// This still asks `translator` to classify `event` — same SQLite/
    /// on-device-model/regex resolution `process(_:)` uses, so a deferred
    /// Play gets exactly the same card-type and ability intelligence an
    /// immediate one would have, not a re-implementation of it here. Only
    /// the physically observed Rune count, which the translator has no way
    /// to know, is patched onto the result before validating.
    public func resolveDeferredPlay(
        for event: ObservedTableEvent,
        observedExhaustedRuneCount: Int?,
        proposedBy player: PlayerID
    ) async -> PlayerInstruction {
        let snapshot = await store.currentState

        guard let candidateAction = await translator.inferAction(
            from: event, in: snapshot, proposedBy: player
        ) else {
            return .unrecognizedEvent(event)
        }

        // The translator gets the final say on what this event means —
        // if it no longer reads as a Play (e.g. the card's since been
        // reclassified), trust that rather than forcing one.
        guard case .play(let card, let destination, let additionalChoices, _) = candidateAction else {
            return await runValidated(candidateAction, in: snapshot, proposedBy: player, fallbackEvent: event)
        }
        let action = GameAction.play(
            card: card,
            destination: destination,
            additionalChoices: additionalChoices,
            observedExhaustedRuneCount: observedExhaustedRuneCount
        )
        return await runValidated(action, in: snapshot, proposedBy: player, fallbackEvent: event)
    }

    /// Shared tail of `process(_:)`/`submitPlay(...)`: validate, and if
    /// legal, apply + Cleanup as one atomic transform through the store
    /// (CLAUDE.md point 2/3), then report whichever consequence outranks a
    /// bare acknowledgement.
    ///
    /// For a `.play`, the played card's ability is parsed *before* that
    /// mutation — `GameActionApplier` stays pure/synchronous and never
    /// talks to `translator` itself (CLAUDE.md point 3), so this is the
    /// one seam that does. A Unit executes its ability immediately inside
    /// the same mutation; a Spell carries it on the `ChainItem` it pushes
    /// and executes it later, whenever that item resolves — either way,
    /// exactly one `store.mutate` call, no separate pass needed afterward.
    private func runValidated(
        _ action: GameAction,
        in snapshot: GameState,
        proposedBy proposer: PlayerID,
        fallbackEvent event: ObservedTableEvent
    ) async -> PlayerInstruction {
        switch LegalityValidator.validate(action, in: snapshot, proposedBy: proposer) {
        case .failure(let reason):
            return .actionRejected(observed: event, reason: reason)

        case .success:
            let abilityInstructions = await abilityInstructions(for: action, in: snapshot, proposedBy: proposer)

            let consequences = ConsequenceBox()
            var abilitySummaries: [String] = []
            _ = await store.mutate { state in
                consequences.events = GameActionApplier.apply(action, to: &state, proposedBy: proposer, abilityInstructions: abilityInstructions)
                state = Cleanup.run(state)
                abilitySummaries = state.abilityOutcomeSummaries
                state.abilityOutcomeSummaries = []
            }
            let followUp = abilitySummaries.isEmpty ? nil : FollowUp(description: abilitySummaries.joined(separator: " "))

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
            return .actionAccepted(action, followUp: followUp)
        }
    }

    /// `.play`'s card, parsed — `[]` for every other `GameAction` (nothing
    /// else in this vocabulary triggers an ability) and for a `.play`
    /// whose card can't be found in `snapshot` (shouldn't happen; caught
    /// as `.cardNotInHand` moments later by `LegalityValidator` regardless,
    /// so this just declines to guess rather than duplicating that check).
    private func abilityInstructions(for action: GameAction, in snapshot: GameState, proposedBy player: PlayerID) async -> [EffectInstruction] {
        guard case .play(let cardID, _, _, _) = action,
              let definitionID = snapshot.zones[player]?.hand.first(where: { $0.id == cardID })?.definitionID else {
            return []
        }
        return await translator.parseAbility(cardDefinitionID: definitionID)
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
