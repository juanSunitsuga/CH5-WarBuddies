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
    /// Resolves a `CardDefID` to what the caller knows about that printing.
    /// Nothing here runs actual OCR: once Stage 1/2 have identified *which*
    /// card this is, its real printed text and name are already known (e.g.
    /// via `RiftboundVision.CardDatabase.printing(riftboundID:)`, keyed the
    /// same way the `CardDefID` was produced). The caller owns that lookup
    /// so this package doesn't need to depend on `RiftboundVision`.
    ///
    /// Returning `nil` means "this card isn't in my catalogue" — a normal
    /// outcome, not a failure. The engine still runs, falling back to its
    /// own SQLite database and then to regex; refusing to translate here
    /// would make those fallbacks unreachable for exactly the unknown
    /// cards they exist to handle.
    private let cardContext: @Sendable (CardDefID) -> CardContext?

    /// Called with a human-readable reason whenever an observed event was
    /// understood but doesn't correspond to a proposable `GameAction`.
    ///
    /// `ActionTranslating.inferAction` can only answer `GameAction?`, so a
    /// `nil` collapses "that isn't an action" (a Battlefield being placed),
    /// "that card isn't in hand," and "the text didn't parse" into one
    /// indistinguishable outcome — which surfaced to players as the
    /// unhelpful "couldn't tell what it meant" for every one of them. This
    /// carries the reason out of band so the UI can say something true
    /// without widening the protocol.
    ///
    /// Invoked synchronously inside `inferAction`, so a caller driving
    /// events serially can read whatever it captured immediately after
    /// `GameEngine.process` returns.
    public var onUntranslatable: (@Sendable (String) -> Void)?

    /// What the host app can tell this package about an identified card.
    public struct CardContext: Sendable {
        /// This package's SQLite `card_id`. The rest of the pipeline keys
        /// cards by `riftbound_id` (`ogn-007-298`) while the database is
        /// keyed by the catalogue's own hex id
        /// (`69bc5bc6d308c64675ca86bc`) — two disjoint ID spaces, so
        /// without this the database lookup can never hit on an ID that
        /// came from the vision pipeline.
        /// `RiftboundVision.CardPrinting.id` is exactly this value; it
        /// matches all 75 rows of the shipped database.
        public let databaseID: String?
        public let name: String?
        public let printedText: String?
        /// Rule 133: this printing's Domain(s), e.g. `[.fury]` for a Fury
        /// Rune, `[.fury, .chaos]` for a dual-Domain Unit. Needed to
        /// resolve `.recycleRune` into a real `GameAction.recycleRune`
        /// (which Domain the recycled Rune actually was) — empty for
        /// callers that don't have it, same "flag rather than guess"
        /// treatment as a missing `printedText`.
        public let domains: [Domain]

        public init(databaseID: String? = nil, name: String?, printedText: String?, domains: [Domain] = []) {
            self.databaseID = databaseID
            self.name = name
            self.printedText = printedText
            self.domains = domains
        }
    }

    public init(
        engine: ActionTranslatingEngine = ActionTranslatingEngine(),
        cardContext: @escaping @Sendable (CardDefID) -> CardContext?
    ) {
        self.engine = engine
        self.cardContext = cardContext
    }

    /// Convenience for callers that only have rules text. Prefer the
    /// `cardContext:` initializer — without a `databaseID` or a name there
    /// is no key that joins to this package's SQLite database, so every
    /// lookup misses and the engine is forced down the CoreML/regex
    /// fallback even for cards the database knows.
    public convenience init(
        engine: ActionTranslatingEngine = ActionTranslatingEngine(),
        printedText: @escaping @Sendable (CardDefID) -> String?
    ) {
        self.init(engine: engine) { CardContext(name: nil, printedText: printedText($0)) }
    }

    /// Stage 3a: `RiftboundExpertSystem.ObservedTableEvent` → `GameAction?`.
    public func inferAction(
        from event: RiftboundExpertSystem.ObservedTableEvent,
        in state: GameState,
        proposedBy player: PlayerID
    ) async -> GameAction? {
        // No identity, nothing to translate — same "not proposable" outcome
        // `ActionTranslating`'s doc comment describes for tracking jitter.
        guard let card = event.card else {
            onUntranslatable?("Something moved, but the recognizer couldn't say which card it was.")
            return nil
        }

        switch event.kind {
        case .cardOrientationChanged(_, let nowExhausted):
            // Rotation isn't a "card was played" signature — Exhaust/Ready
            // (rules 592/593) is handled elsewhere in the pipeline, not by
            // this translator.
            onUntranslatable?("Turned \(nowExhausted ? "sideways (exhausted)" : "upright (readied)") — tracked, but not a move to propose.")
            return nil

        case .cardRemoved:
            // Leaving play is Cleanup's business, not a proposable action.
            onUntranslatable?("Left the table — removal is resolved during Cleanup, not proposed as a move.")
            return nil

        case .cardAppeared(let region):
            guard !region.isHandRegion else {
                // A card newly visible *in hand* isn't a play — it's the
                // camera catching up to a card that was already there
                // (game start, hand reshuffled into view). Nothing to infer.
                onUntranslatable?("Came into view in the hand — nothing was played.")
                return nil
            }
            return await translate(card: card, from: nil, to: region, state: state, player: player)

        case .cardMoved(let from, let to):
            // Two moves are recognisable from the transition alone, without
            // asking the card-text layer what the card does.
            if from.zone == .mainDeck, to.isHandRegion {
                // Rule 591: Draw. A Limited Action (589.2) — legal only
                // when something has already authorized it, which the
                // validator checks. Proposing it is right; deciding whether
                // it was allowed is the engine's job, not this layer's.
                return .draw(count: 1)
            }
            if from.zone == .runeDeck, to.zone == .runeArea {
                // Rule 515.3/154.3: Channel Rune, also a Limited Action.
                // Reachable at last now that `.runeArea` can be named —
                // previously this branch could never be entered.
                onUntranslatable?("Channelling a Rune is a scripted step of the Channel Phase, not a move to propose.")
                return nil
            }
            return await translate(card: card, from: from, to: to, state: state, player: player)
        }
    }

    /// Stage 3b: card text → structured effects (`CardAbilityParser`).
    ///
    /// Falls back to the card's own printed text when `rawText` is empty:
    /// the caller often has only a `CardDefID`, and this package's database
    /// knows the text for every printing it ships. Refusing to parse
    /// because the *caller* didn't supply text would make the common path
    /// the useless one.
    ///
    /// Targeted effects come back with `TargetSpec.placeholder`, because
    /// that type is still a placeholder in the engine by design — until it
    /// can express "a unit at a battlefield", the *summary* on
    /// `ParsedAbility` is what carries the meaning, and
    /// `abilitySummaries(for:)` is what the UI should show. What this does
    /// give the engine today is the untargeted cases — Draw, Channel,
    /// Discard — which are exactly the ones it can already apply.
    public func parseAbility(rawText: String, cardDefinitionID: CardDefID) async -> [EffectInstruction] {
        CardAbilityParser.instructions(for: text(rawText, or: cardDefinitionID))
    }

    /// The same parse, keyed by card alone — what `GameEngine` calls when a
    /// card it just played needs resolving. The text comes from this
    /// package's corpus, which is the whole reason the engine can ask at
    /// all: it holds `ObjectID`s and a `GameState`, never card text.
    public func abilities(of cardDefinitionID: CardDefID) async -> [EffectInstruction] {
        await parseAbility(rawText: "", cardDefinitionID: cardDefinitionID)
    }

    /// Player-facing reading of a card's abilities, each named by the Game
    /// Action it resolves to (586–607). What the app puts on screen when a
    /// card is played or selected.
    public func abilitySummaries(for cardDefinitionID: CardDefID, rawText: String = "") -> [ParsedAbility] {
        CardAbilityParser.read(text(rawText, or: cardDefinitionID)).abilities
    }

    private func text(_ rawText: String, or cardDefinitionID: CardDefID) -> String {
        guard rawText.isEmpty else { return rawText }
        return cardContext(cardDefinitionID)?.printedText ?? ""
    }

    // MARK: - Translation

    private func translate(
        card: CardIdentification,
        from: TableRegion?,
        to: TableRegion,
        state: GameState,
        player: PlayerID
    ) async -> GameAction? {
        // An unknown card is still translatable — the engine's own SQLite
        // lookup and regex fallback exist for exactly this case, and
        // bailing here would make them dead code.
        let context = cardContext(card.cardDefinitionID)

        let internalEvent = ObservedTableEvent(
            cardID: card.cardDefinitionID.rawValue,
            databaseID: context?.databaseID,
            cardName: context?.name,
            ocrText: context?.printedText ?? "",
            // Deliberately not `?? "Hand"`: `from` is nil when the card's
            // origin was never observed (it appeared already on the board,
            // or its track dropped and was re-acquired). Defaulting that to
            // the hand reports a missed observation as a confident play.
            sourceRegion: from.map(regionName),
            destinationRegion: regionName(to)
        )

        let candidate = await engine.inferAction(event: internalEvent)
        return gameAction(for: candidate, context: context, destination: to, state: state, player: player)
    }

    /// Maps a `TableRegion` onto the region names `ActionTranslatingEngine`
    /// compares against.
    ///
    /// Every zone is nameable now. Previously only Hand, Base and
    /// Battlefield existed, so `"RuneArea"` could never be produced and the
    /// `.channelRune` branch was unreachable no matter what a player did on
    /// the table.
    private func regionName(_ region: TableRegion) -> String {
        switch region.zone {
        case .hand: return "Hand"
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case .mainDeck: return "MainDeck"
        case .runeDeck: return "RuneDeck"
        case .runeArea: return "RuneArea"
        case .trash: return "Trash"
        case .banishment: return "Banishment"
        case .legendZone: return "Legend"
        case .championZone: return "Champion"
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
        context: CardContext?,
        destination: TableRegion,
        state: GameState,
        player: PlayerID
    ) -> GameAction? {
        switch candidate {
        case .playUnit(let cardID, let cardName, _, _, _), .castSpell(let cardID, let cardName, _, _):
            guard let objectID = handObjectID(definitionID: CardDefID(rawValue: cardID), player: player, in: state) else {
                onUntranslatable?("\(cardName) isn't in the hand the engine is tracking, so playing it can't be resolved.")
                return nil
            }
            return .play(card: objectID, destination: playDestination(destination), additionalChoices: [])

        case .channelRune:
            // Rule 154.3/589.2: Channel Rune is a Limited Action — only
            // ever performed at a fixed turn-structure point (515.3) or by
            // an effect, never freely proposed by a player. Still
            // translate it to `.channel`, though: a Rune physically
            // landing in the Rune Area is evidence the Channel Phase's own
            // scripted action already authorized it
            // (`GameState.authorize`), and `LegalityValidator` is exactly
            // what checks that evidence against the authorization ledger —
            // an unauthorized physical Channel correctly comes back
            // rejected, same anti-cheat mechanism as everything else here.
            return .channel(count: 1, exhausted: false)

        case .recycleRune(_, let cardName):
            // Rule 130.3/589.2 — same reasoning as `.channelRune` above,
            // reversed direction. See `GameAction.recycleRune`'s doc
            // comment for why this is a Domain-only sibling of `.recycle`
            // rather than reusing it.
            guard let domain = context?.domains.first else {
                onUntranslatable?("Recycled \(cardName), but its Domain isn't known here, so the Power payment can't be resolved.")
                return nil
            }
            return .recycleRune(domain: domain)

        case .rejected(let reason):
            onUntranslatable?(reason)
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
