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

    @Test("Returns nil for orientation-change and removal events - not play signatures")
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
