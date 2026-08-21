import Testing
@testable import RiftboundExpertSystem

/// Architecture item 7b: a card's text changing `GameState`.
///
/// The dividing line under test is *what may be applied at all*. An
/// instruction with a real count and no choice in it is applied; anything
/// carrying a placeholder target, or any choice of which card, is handed
/// back to the player as a sentence. Getting that line wrong in the
/// permissive direction invents a board nobody decided on.
@Suite("Effect Executor")
struct EffectExecutorTests {

    /// The shared fixture ships an empty Main Deck, so a Draw would be a
    /// no-op and the test would pass without proving anything. Seeded here
    /// rather than in the fixture, so no other suite's counts move.
    private func state(deckSize: Int = 5) -> (GameState, PlayerID) {
        let fixture = TestFixtures.makeTwoPlayerState()
        var game = fixture.state
        let player = fixture.playerA
        game.zones[player]?.mainDeck = (0..<deckSize).map { index in
            MainDeckCard(
                definitionID: CardDefID(rawValue: "test-card-\(index)"),
                owner: player,
                name: "Test Card \(index)",
                type: .spell,
                cost: Cost()
            )
        }
        return (game, player)
    }

    // MARK: - Applied

    @Test("Draw moves cards from the deck into the hand")
    func drawIsApplied() {
        var (game, player) = state()
        let before = game.zones[player]?.hand.count ?? 0
        let deckBefore = game.zones[player]?.mainDeck.count ?? 0

        let outcome = EffectExecutor.run([.draw(count: 2)], on: &game, player: player)

        #expect(outcome.applied == [.draw(count: 2)])
        #expect(outcome.deferred.isEmpty)
        #expect(game.zones[player]?.hand.count == before + 2)
        #expect(game.zones[player]?.mainDeck.count == deckBefore - 2)
    }

    /// 157.2.a — Add is the one effect that puts Energy in a pool without
    /// anything being chosen.
    @Test("Add resources reaches the rune pool")
    func addResourcesIsApplied() {
        var (game, player) = state()
        let before = game.zones[player]?.runePool.energy ?? 0

        let outcome = EffectExecutor.run([.addResources(energy: 2, power: [])], on: &game, player: player)

        #expect(outcome.applied.count == 1)
        #expect(game.zones[player]?.runePool.energy == before + 2)
    }

    @Test("Several applicable effects all run, in order")
    func multipleApplied() {
        var (game, player) = state()
        let handBefore = game.zones[player]?.hand.count ?? 0
        let energyBefore = game.zones[player]?.runePool.energy ?? 0

        let outcome = EffectExecutor.run(
            [.draw(count: 1), .addResources(energy: 1, power: [])],
            on: &game, player: player
        )

        #expect(outcome.applied.count == 2)
        #expect(game.zones[player]?.hand.count == handBefore + 1)
        #expect(game.zones[player]?.runePool.energy == energyBefore + 1)
    }

    // MARK: - Deferred

    /// The important half. A placeholder target means the engine cannot
    /// know what the effect hits, so it must not touch the board.
    @Test("A targeted effect is never applied, only reported")
    func targetedEffectsAreDeferred() {
        var (game, player) = state()
        let snapshot = game

        let outcome = EffectExecutor.run(
            [.killUnit(targets: .placeholder),
             .dealDamage(amount: 3, targets: .placeholder),
             .buff(targets: .placeholder)],
            on: &game, player: player
        )

        #expect(outcome.applied.isEmpty)
        #expect(outcome.deferred.count == 3)
        // Nothing moved.
        #expect(game.zones[player]?.hand.count == snapshot.zones[player]?.hand.count)
        #expect(game.zones[player]?.mainDeck.count == snapshot.zones[player]?.mainDeck.count)
    }

    /// 594.3: "discard 2" doesn't say which 2, and a count is not a target.
    /// This one is deliberately *not* executed even though it carries a
    /// real number.
    @Test("Discard is deferred, because which card is the player's choice")
    func discardIsDeferred() {
        var (game, player) = state()
        let before = game.zones[player]?.hand.count ?? 0

        let outcome = EffectExecutor.run([.discard(count: 2)], on: &game, player: player)

        #expect(outcome.applied.isEmpty)
        #expect(outcome.deferred == ["Discard 2 cards."])
        #expect(game.zones[player]?.hand.count == before)
    }

    /// The condition itself is a placeholder, so the engine can't even tell
    /// which branch applies — let alone run one.
    @Test("A conditional effect is deferred whole")
    func conditionalIsDeferred() {
        var (game, player) = state()
        let before = game.zones[player]?.hand.count ?? 0

        let outcome = EffectExecutor.run(
            [.conditional(condition: .placeholder, then: [.draw(count: 5)], else_: [])],
            on: &game, player: player
        )

        #expect(outcome.applied.isEmpty)
        #expect(game.zones[player]?.hand.count == before)
    }

    /// A parse that produced "draw 0" is a parser bug. Silently doing
    /// nothing would hide it; the player is told instead.
    @Test("A degenerate count is reported rather than silently skipped")
    func zeroCountIsReported() {
        var (game, player) = state()

        let outcome = EffectExecutor.run([.draw(count: 0)], on: &game, player: player)

        #expect(outcome.applied.isEmpty)
        #expect(outcome.deferred.count == 1)
    }

    @Test("No instructions produces nothing to say")
    func emptyIsEmpty() {
        var (game, player) = state()
        #expect(EffectExecutor.run([], on: &game, player: player).isEmpty)
    }
}

/// The wiring, end to end through `GameEngine.process`: a played card's text
/// changing `GameState` and coming back as something to tell the player.
@Suite("Played card effects")
struct PlayedCardEffectTests {

    private func engineAndState(
        abilities: [EffectInstruction]
    ) -> (GameEngine, GameStateStore, PlayerID, ObjectID) {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()

        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell-under-test"),
            owner: playerA,
            name: "Spell Under Test",
            type: .spell,
            cost: Cost()
        )
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.mainDeck = (0..<5).map { index in
            MainDeckCard(
                definitionID: CardDefID(rawValue: "deck-\(index)"),
                owner: playerA,
                name: "Deck Card \(index)",
                type: .spell,
                cost: Cost()
            )
        }

        let store = GameStateStore(initialState: state)
        var translator = FixedActionTranslator(
            action: .play(card: card.id, destination: .base(playerA), additionalChoices: [])
        )
        translator.cardAbilities = abilities

        let engine = GameEngine(store: store, observer: NeverObserving(), translator: translator)
        return (engine, store, playerA, card.id)
    }

    /// The engine attributes the event to a player through its region, so
    /// the owner has to be the player under test.
    private func playEvent(for player: PlayerID) -> ObservedTableEvent {
        ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: player, location: .base(player), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )
    }

    /// The claim this whole change rests on: card text reaches `GameState`.
    @Test("Playing a card with 'draw 2' actually draws 2")
    func playedCardDraws() async {
        let (engine, store, player, _) = engineAndState(abilities: [.draw(count: 2)])
        let before = await store.currentState.zones[player]?.hand.count ?? 0

        let instruction = await engine.process(playEvent(for: player))

        let after = await store.currentState.zones[player]?.hand.count ?? 0
        // -1 for the card that left hand to be played, +2 drawn.
        #expect(after == before - 1 + 2)

        guard case .actionAccepted(_, let followUp) = instruction else {
            Issue.record("Expected the play to be accepted, got \(instruction)")
            return
        }
        #expect(followUp?.description.contains("drew 2 cards") == true)
    }

    /// And the other half: what it can't run, the player is told to do.
    @Test("A targeted effect comes back as an instruction, not a state change")
    func playedCardDefersTargeting() async {
        let (engine, store, player, _) = engineAndState(abilities: [.killUnit(targets: .placeholder)])
        let unitsBefore = await store.currentState.units.count

        let instruction = await engine.process(playEvent(for: player))

        #expect(await store.currentState.units.count == unitsBefore)
        _ = player

        guard case .actionAccepted(_, let followUp) = instruction else {
            Issue.record("Expected the play to be accepted, got \(instruction)")
            return
        }
        #expect(followUp?.description.contains("Kill a unit") == true)
    }

    /// A card with no text must not invent a follow-up out of nothing.
    @Test("A card with no abilities produces no follow-up")
    func noAbilitiesNoFollowUp() async {
        let (engine, _, player, _) = engineAndState(abilities: [])

        guard case .actionAccepted(_, let followUp) = await engine.process(playEvent(for: player)) else {
            Issue.record("Expected the play to be accepted")
            return
        }
        #expect(followUp == nil)
    }
}
