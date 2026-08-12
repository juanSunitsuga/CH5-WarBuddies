import RiftboundExpertSystem

/// Makes `ActionTranslatingEngine` (this package's CoreML + regex card-text
/// pipeline) satisfy `RiftboundExpertSystem.ActionTranslating` — the
/// contract `GameEngine` actually calls. `ActionTranslatingEngine` was
/// built with its own `ObservedTableEvent`/`CandidateGameAction` shapes
/// (a plain `cardID: String` + `ocrText` + string region names) before
/// this package depended on `RiftboundExpertSystem` directly; rather than
/// reshaping either side to match the other, this is the one place that
/// translates between them — same seam philosophy as `RiftboundVision`'s
/// `ExpertSystemAdapter` (translate at the boundary, don't leak one
/// package's shapes into another's).
///
/// Both packages define a type named `ObservedTableEvent`. Every use below
/// is qualified (`RiftboundExpertSystem.ObservedTableEvent` vs the plain,
/// unqualified `ObservedTableEvent` that resolves to this module's own
/// type) — don't remove the qualification, it's load-bearing, not stylistic.
///
/// `@unchecked Sendable`: `ActionTranslatingEngine` itself isn't
/// `Sendable`-annotated (it wraps CoreML model handles the same way
/// `RiftboundVision.CoreMLCardDetector` does, which uses the same escape
/// hatch) — same single-writer-per-call contract as the rest of this
/// pipeline's adapters.
public final class ExpertSystemTranslatorAdapter: ActionTranslating, @unchecked Sendable {
    private let engine: ActionTranslatingEngine
    /// Resolves a `CardDefID` to its real printed rules text. This is the
    /// simplification noted in the pipeline writeup: `ActionTranslatingEngine
    /// .inferAction` asks for `ocrText`, but nothing here runs actual OCR —
    /// once Stage 1/2 have identified *which* card this is, its real
    /// printed text is already known (e.g. via `RiftboundVision.CardDatabase
    /// .printing(riftboundID:)?.text.plain`, keyed the same way `identify
    /// (objectID:as:)` populated the `CardDefID` in the first place). The
    /// caller owns that lookup so this package doesn't need to depend on
    /// `RiftboundVision`.
    private let printedText: @Sendable (CardDefID) -> String?

    public init(engine: ActionTranslatingEngine = ActionTranslatingEngine(), printedText: @escaping @Sendable (CardDefID) -> String?) {
        self.engine = engine
        self.printedText = printedText
    }

    /// Stage 3a: `RiftboundExpertSystem.ObservedTableEvent` → `GameAction?`.
    public func inferAction(
        from event: RiftboundExpertSystem.ObservedTableEvent,
        in state: GameState,
        proposedBy player: PlayerID
    ) async -> GameAction? {
        // No identity, nothing to translate — same "not proposable" outcome
        // `ActionTranslating`'s doc comment describes for tracking jitter.
        guard let card = event.card else { return nil }

        switch event.kind {
        case .cardOrientationChanged, .cardRemoved:
            // Rotation and removal aren't "a card was played" signatures —
            // Exhaust/Ready and leaving-play are handled elsewhere in the
            // pipeline (rules 592/593, Cleanup), not by this translator.
            return nil

        case .cardAppeared(let region):
            guard !region.isHandRegion else {
                // A card newly visible *in hand* isn't a play — it's the
                // camera catching up to a card that was already there
                // (game start, hand reshuffled into view). Nothing to infer.
                return nil
            }
            return await translate(card: card, from: nil, to: region, state: state, player: player)

        case .cardMoved(let from, let to):
            return await translate(card: card, from: from, to: to, state: state, player: player)
        }
    }

    /// Stage 3b: card text → structured effects. `ActionTranslatingEngine`
    /// doesn't implement ability parsing at all yet (it only infers *that*
    /// a card was played, not what its ability does) — flagging this gap
    /// rather than inventing behavior, per CLAUDE.md point 4.
    public func parseAbility(rawText: String, cardDefinitionID: CardDefID) async -> [EffectInstruction] {
        []
    }

    // MARK: - Translation

    private func translate(
        card: CardIdentification,
        from: TableRegion?,
        to: TableRegion,
        state: GameState,
        player: PlayerID
    ) async -> GameAction? {
        guard let rawText = printedText(card.cardDefinitionID) else { return nil }

        let internalEvent = ObservedTableEvent(
            cardID: card.cardDefinitionID.rawValue,
            ocrText: rawText,
            sourceRegion: from.map(regionName) ?? "Hand",
            destinationRegion: regionName(to)
        )

        let candidate = await engine.inferAction(event: internalEvent)
        return gameAction(for: candidate, destination: to, state: state, player: player)
    }

    /// Maps a `TableRegion` to the exact region-name strings
    /// `ActionTranslatingEngine`'s heuristics compare against
    /// (`"Hand"`/`"Base"`/`"Battlefield"`). `TableRegion` can only
    /// represent those three (rule 106.5.b — see `RiftboundVision
    /// .ExpertSystemAdapter`'s own doc comment on the same gap), which
    /// means `.channelRune` (checked via `destinationRegion == "RuneArea"`)
    /// can never actually fire through this real path — `TableRegion` has
    /// no Rune Area representation to produce that string from. Flagging,
    /// not working around: fixing this means extending `TableRegion`
    /// itself (`RiftboundExpertSystem`), not inventing a parallel region
    /// vocabulary here.
    private func regionName(_ region: TableRegion) -> String {
        if region.isHandRegion { return "Hand" }
        switch region.location {
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case nil: return "Hand"
        }
    }

    /// `CandidateGameAction` → the real, closed-vocabulary `GameAction`.
    /// The one piece this needs that nothing else in the pipeline
    /// provides: which *existing* `ObjectID` in `state` this observed card
    /// actually is. Hand cards are matched by `CardDefID` (rule 131 — same
    /// name means same definition), not by tracked physical identity,
    /// since no `TrackedObjectID → ObjectID` registry exists anywhere in
    /// this pipeline yet. If the player has two identical cards in hand
    /// this picks whichever sorts first — a real but narrow ambiguity, not
    /// a silent wrong answer (both candidates are the same `CardDefID`, so
    /// the resulting `GameAction` is correct either way for anything that
    /// doesn't care *which* physical copy).
    private func gameAction(
        for candidate: CandidateGameAction,
        destination: TableRegion,
        state: GameState,
        player: PlayerID
    ) -> GameAction? {
        switch candidate {
        case .playUnit(let cardID, _, _, _, _), .castSpell(let cardID, _, _, _):
            guard let objectID = handObjectID(definitionID: CardDefID(rawValue: cardID), player: player, in: state) else {
                return nil
            }
            return .play(card: objectID, destination: playDestination(destination), additionalChoices: [])

        case .channelRune:
            // Rule 154.3/589.2: Channel Rune is a Limited Action — only
            // ever performed at a fixed turn-structure point (515.3) or by
            // an effect, never freely proposed by a player. A Rune
            // physically landing in the Rune Area is evidence *of* the
            // Channel Phase's own scripted action already having
            // authorized it (`GameState.authorize`), not a new
            // Discretionary action to propose here. Nothing to translate —
            // this also can never actually be reached today, since
            // `regionName` can't produce "RuneArea" (see its doc comment).
            return nil

        case .rejected:
            return nil
        }
    }

    private func handObjectID(definitionID: CardDefID, player: PlayerID, in state: GameState) -> ObjectID? {
        state.zones[player]?.hand.first { $0.definitionID == definitionID }?.id
    }

    private func playDestination(_ region: TableRegion) -> PlayDestination {
        switch region.location {
        case .base(let ownerID): return .base(ownerID)
        case .battlefield(let battlefieldID): return .battlefield(battlefieldID)
        case nil: return .none
        }
    }
}
