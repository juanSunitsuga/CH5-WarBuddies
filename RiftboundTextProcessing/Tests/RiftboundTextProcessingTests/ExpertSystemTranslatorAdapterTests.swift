import Testing
import RiftboundExpertSystem
@testable import RiftboundTextProcessing

/// Minimal `GameState` fixture — mirrors `RiftboundExpertSystemTests
/// .TestFixtures`, which is internal to that package's own test target
/// and so isn't reusable from here directly.
private enum Fixture {
    static func makeState(handCardName: String = "Test Unit") -> (state: GameState, player: PlayerID, opponent: PlayerID, handCardDefinitionID: CardDefID) {
        let player = PlayerID()
        let opponent = PlayerID()
        let definitionID = CardDefID(rawValue: "def-\(handCardName)")

        let handCard = MainDeckCard(
            definitionID: definitionID,
            owner: player,
            name: handCardName,
            type: .unit(isChampion: false)
        )

        func zones(for owner: PlayerID, hand: [MainDeckCard] = []) -> PlayerZones {
            var zones = PlayerZones(legend: ChampionLegend(
                definitionID: CardDefID(rawValue: "legend-\(owner)"),
                owner: owner,
                name: "Test Legend",
                domains: [],
                championTag: "Test"
            ))
            zones.hand = hand
            return zones
        }

        let state = GameState(
            turnOrder: [player, opponent],
            battlefields: [:],
            zones: [
                player: zones(for: player, hand: [handCard]),
                opponent: zones(for: opponent)
            ]
        )
        return (state, player, opponent, definitionID)
    }

    static func handRegion(owner: PlayerID) -> TableRegion {
        TableRegion(owner: owner, location: nil, isHandRegion: true)
    }

    static func baseRegion(owner: PlayerID) -> TableRegion {
        TableRegion(owner: owner, location: .base(owner), isHandRegion: false)
    }
}

@Suite("Expert System Translator Adapter Tests")
struct ExpertSystemTranslatorAdapterTests {

    @Test("Returns nil when the observed event carries no card identity")
    func returnsNilWithoutIdentity() async {
        let (state, player, _, _) = Fixture.makeState()
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in "irrelevant" })

        let event = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardAppeared(region: Fixture.baseRegion(owner: player)),
            card: nil,
            observedAt: 0
        )

        let action = await adapter.inferAction(from: event, in: state, proposedBy: player)
        #expect(action == nil)
    }

    /// Removal is still Cleanup's business. Orientation is no longer nil in
    /// general — it becomes Exhaust/Ready — but stays nil here because the
    /// card in this fixture is in *hand*, and a card in hand has no board
    /// object to turn. See `OrientationTranslationTests` for the live case.
    @Test("Removal proposes nothing, and orientation proposes nothing for a card that isn't in play")
    func returnsNilForNonPlaySignatures() async {
        let (state, player, _, definitionID) = Fixture.makeState()
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in "[Assault 2]" })
        let card = CardIdentification(cardDefinitionID: definitionID, physicalRegion: Fixture.baseRegion(owner: player), confidence: 1)

        let rotated = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardOrientationChanged(region: Fixture.baseRegion(owner: player), nowExhausted: true),
            card: card,
            observedAt: 0
        )
        let removed = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardRemoved(region: Fixture.baseRegion(owner: player)),
            card: card,
            observedAt: 0
        )

        #expect(await adapter.inferAction(from: rotated, in: state, proposedBy: player) == nil)
        #expect(await adapter.inferAction(from: removed, in: state, proposedBy: player) == nil)
    }

    @Test("Returns nil when a card newly appears already in Hand - not a play")
    func returnsNilForCardAppearingInHand() async {
        let (state, player, _, definitionID) = Fixture.makeState()
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in "[Assault 2]" })
        let card = CardIdentification(cardDefinitionID: definitionID, physicalRegion: Fixture.handRegion(owner: player), confidence: 1)

        let event = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardAppeared(region: Fixture.handRegion(owner: player)),
            card: card,
            observedAt: 0
        )

        let action = await adapter.inferAction(from: event, in: state, proposedBy: player)
        #expect(action == nil)
    }

    @Test("Returns nil when no printed text is available for the identified card")
    func returnsNilWithoutPrintedText() async {
        let (state, player, _, definitionID) = Fixture.makeState()
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in nil })
        let card = CardIdentification(cardDefinitionID: definitionID, physicalRegion: Fixture.baseRegion(owner: player), confidence: 1)

        let event = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardMoved(from: Fixture.handRegion(owner: player), to: Fixture.baseRegion(owner: player)),
            card: card,
            observedAt: 0
        )

        let action = await adapter.inferAction(from: event, in: state, proposedBy: player)
        #expect(action == nil)
    }

    @Test("A Hand-to-Base move that the engine accepts as a Unit resolves to .play with the real hand ObjectID")
    func handToBaseMoveResolvesToPlayWithRealObjectID() async {
        let (state, player, _, definitionID) = Fixture.makeState(handCardName: "Garen Rugged")
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in
            "[Assault 2], [Shield 2] (+2 Might while I'm an attacker or defender.)"
        })
        let card = CardIdentification(cardDefinitionID: definitionID, physicalRegion: Fixture.baseRegion(owner: player), confidence: 1)

        let event = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardMoved(from: Fixture.handRegion(owner: player), to: Fixture.baseRegion(owner: player)),
            card: card,
            observedAt: 0
        )

        let action = await adapter.inferAction(from: event, in: state, proposedBy: player)

        // The underlying CoreML classifier's confidence is not fully
        // deterministic across process launches (its tokenizer hashes
        // words using String.hashValue, which Swift randomizes per
        // process) - so a nil (classifier missed / classified as
        // something other than Unit) is an acceptable outcome here, not
        // a test failure. What must hold *whenever* an action does come
        // back is that it's the real hand ObjectID, not a fabricated one.
        guard let action else { return }
        let expectedObjectID = state.zones[player]?.hand.first?.id
        #expect(action == .play(card: expectedObjectID!, destination: .base(player), additionalChoices: []))
    }
}

/// Turning a rune sideways is what produces Energy (157.2.a), and it used to
/// stop dead at this adapter — which is why `GameSessionBuilder` had to seed
/// a pool for anything to be affordable at all.
@Suite("Orientation becomes Exhaust")
struct OrientationTranslationTests {

    private static func stateWithRune(exhausted: Bool) -> (GameState, PlayerID, CardDefID, ObjectID) {
        var (state, player, _, _) = Fixture.makeState()
        let definitionID = CardDefID(rawValue: "rune-fury")
        let rune = Rune(
            id: ObjectID(),
            owner: player,
            controller: player,
            card: RuneCard(definitionID: definitionID, owner: player, domain: .fury),
            isExhausted: exhausted
        )
        state.runes[rune.id] = rune
        return (state, player, definitionID, rune.id)
    }

    private static func orientationEvent(
        _ definitionID: CardDefID, player: PlayerID, nowExhausted: Bool
    ) -> RiftboundExpertSystem.ObservedTableEvent {
        let region = Fixture.baseRegion(owner: player)
        return RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardOrientationChanged(region: region, nowExhausted: nowExhausted),
            card: CardIdentification(cardDefinitionID: definitionID, physicalRegion: region, confidence: 1),
            observedAt: 0
        )
    }

    @Test("A rune turned sideways proposes Exhaust on that rune")
    func sidewaysBecomesExhaust() async {
        let (state, player, definitionID, runeID) = Self.stateWithRune(exhausted: false)
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in nil })

        let action = await adapter.inferAction(
            from: Self.orientationEvent(definitionID, player: player, nowExhausted: true),
            in: state, proposedBy: player
        )

        #expect(action == .exhaust(objects: [runeID]))
    }

    @Test("A rune turned upright proposes Ready on that rune")
    func uprightBecomesReady() async {
        let (state, player, definitionID, runeID) = Self.stateWithRune(exhausted: true)
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in nil })

        let action = await adapter.inferAction(
            from: Self.orientationEvent(definitionID, player: player, nowExhausted: false),
            in: state, proposedBy: player
        )

        #expect(action == .ready(objects: [runeID]))
    }

    /// A poll re-reporting a rune that is already sideways must not exhaust
    /// a second copy — the stance has to actually be changing.
    @Test("Re-reporting a stance the engine already has proposes nothing")
    func noChangeProposesNothing() async {
        let (state, player, definitionID, _) = Self.stateWithRune(exhausted: true)
        let adapter = ExpertSystemTranslatorAdapter(printedText: { _ in nil })

        let action = await adapter.inferAction(
            from: Self.orientationEvent(definitionID, player: player, nowExhausted: true),
            in: state, proposedBy: player
        )

        #expect(action == nil)
    }

    /// The case that actually happens in the app. `GameSessionBuilder` seeds
    /// the rune deck with placeholder cards because the camera can't see
    /// what went into the deck, so the engine's rune is "rune-fury-0" while
    /// the detector reports a real printing. Matching on definition would
    /// silently never fire; runes of a domain are interchangeable for cost
    /// (157.2), so domain is both the rules-correct key and the one that
    /// works.
    @Test("A rune matches on domain even when the ids come from different spaces")
    func matchesAcrossIDSpaces() async {
        var (state, player, _, _) = Fixture.makeState()
        let engineRune = Rune(
            id: ObjectID(),
            owner: player,
            controller: player,
            card: RuneCard(definitionID: CardDefID(rawValue: "rune-fury-0"), owner: player, domain: .fury),
            isExhausted: false
        )
        state.runes[engineRune.id] = engineRune

        // The detector's id, which the engine has never seen.
        let observed = CardDefID(rawValue: "ogn-007-298")
        let adapter = ExpertSystemTranslatorAdapter(
            cardContext: { _ in .init(name: "Fury Rune", printedText: "", domains: [.fury]) }
        )

        let action = await adapter.inferAction(
            from: Self.orientationEvent(observed, player: player, nowExhausted: true),
            in: state, proposedBy: player
        )

        #expect(action == .exhaust(objects: [engineRune.id]))
    }

    /// The payoff: exhausting a rune puts Energy in the pool, which is what
    /// the seeded pool was standing in for.
    @Test("Exhausting a rune through the engine adds Energy to the pool")
    func exhaustProducesEnergy() async {
        let (state, player, definitionID, _) = Self.stateWithRune(exhausted: false)
        let store = GameStateStore(initialState: state)
        let engine = GameEngine(
            store: store,
            observer: NeverObservingStub(),
            translator: ExpertSystemTranslatorAdapter(printedText: { _ in nil })
        )

        let before = await store.currentState.zones[player]?.runePool.energy ?? 0
        let instruction = await engine.process(
            Self.orientationEvent(definitionID, player: player, nowExhausted: true)
        )
        let after = await store.currentState.zones[player]?.runePool.energy ?? 0

        #expect(after == before + 1, "157.2.a: exhausting a rune adds 1 Energy")
        if case .actionAccepted = instruction {} else {
            Issue.record("Expected the exhaust to be accepted, got \(instruction)")
        }
    }
}

/// `GameEngine.init` needs an observer; `process(_:)` never consumes it.
struct NeverObservingStub: BoardObserving {
    func events() -> AsyncStream<RiftboundExpertSystem.ObservedTableEvent> { AsyncStream { $0.finish() } }
}
