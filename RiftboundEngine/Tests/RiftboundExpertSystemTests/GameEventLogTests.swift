import Testing
@testable import RiftboundExpertSystem

/// The log's one real obligation: a replay has to produce the board that was
/// actually played, not merely a plausible one.
///
/// Everything the log is for — resume, correction, `GameState` becoming
/// derived rather than separately maintained — rests on `state(through:)`
/// agreeing with what `GameEngine.process` did live. If those two ever
/// diverge, a resumed game silently isn't the game the player left.
@Suite("Game Event Log")
struct GameEventLogTests {

    /// Enough of a board to draw from and play onto.
    private func fixture(deckSize: Int = 6) -> (GameState, PlayerID, MainDeckCard) {
        let fixture = TestFixtures.makeTwoPlayerState()
        var state = fixture.state
        let player = fixture.playerA

        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell-under-test"),
            owner: player,
            name: "Spell Under Test",
            type: .spell,
            cost: Cost()
        )
        state.zones[player]?.hand.append(card)
        state.zones[player]?.mainDeck = (0..<deckSize).map { index in
            MainDeckCard(
                definitionID: CardDefID(rawValue: "deck-\(index)"),
                owner: player,
                name: "Deck Card \(index)",
                type: .spell,
                cost: Cost()
            )
        }
        return (state, player, card)
    }

    /// Compares the parts of `GameState` a player would notice. `GameState`
    /// isn't `Equatable` — it carries tuples that block synthesis — so this
    /// names the fields rather than pretending to a whole-value comparison
    /// it can't make.
    private func expectSameBoard(_ a: GameState, _ b: GameState, _ note: String) {
        for player in a.zones.keys {
            #expect(a.zones[player]?.hand.count == b.zones[player]?.hand.count, "\(note): hand")
            #expect(a.zones[player]?.mainDeck.count == b.zones[player]?.mainDeck.count, "\(note): deck")
            #expect(a.zones[player]?.runePool.energy == b.zones[player]?.runePool.energy, "\(note): energy")
        }
        #expect(a.units.count == b.units.count, "\(note): units")
        #expect(a.runes.count == b.runes.count, "\(note): runes")
    }

    // MARK: - Replay

    @Test("An empty log replays to exactly the state it started from")
    func emptyLogIsIdentity() {
        let (state, player, _) = fixture()
        let log = GameEventLog(initialState: state)

        #expect(log.isEmpty)
        expectSameBoard(log.state(), state, "empty replay")
        #expect(log.state().zones[player]?.hand.count == state.zones[player]?.hand.count)
    }

    @Test("Replaying reproduces the board the actions produced")
    func replayMatchesDirectApplication() {
        let (start, player, _) = fixture()

        // Apply live, the way `process` does.
        var live = start
        for count in [1, 2] {
            _ = GameActionApplier.apply(.draw(count: count), to: &live, proposedBy: player, abilityInstructions: [])
            live = Cleanup.run(live)
            live.abilityOutcomeSummaries = []
        }

        // The same actions, recorded and replayed.
        var log = GameEventLog(initialState: start)
        log.record(action: .draw(count: 1), proposer: player)
        log.record(action: .draw(count: 2), proposer: player)

        expectSameBoard(log.state(), live, "replay vs live")
        #expect(log.state().zones[player]?.hand.count == (start.zones[player]?.hand.count ?? 0) + 3)
    }

    /// Resume: come back to where you were, not to the end of the game.
    @Test("Replaying through an entry stops there")
    func replayIsAddressable() {
        let (start, player, _) = fixture()
        var log = GameEventLog(initialState: start)
        let first = log.record(action: .draw(count: 1), proposer: player)
        log.record(action: .draw(count: 1), proposer: player)

        let handAtStart = start.zones[player]?.hand.count ?? 0
        #expect(log.state(through: first.id).zones[player]?.hand.count == handAtStart + 1)
        #expect(log.state().zones[player]?.hand.count == handAtStart + 2)
    }

    /// Cleanup runs per entry, not once at the end — batching it would let
    /// the board sit in a state the rules never allow between actions.
    @Test("Ability outcome summaries are consumed each entry, not accumulated")
    func summariesDoNotAccumulate() {
        let (start, player, card) = fixture()
        var log = GameEventLog(initialState: start)
        log.record(
            action: .play(card: card.id, destination: .base(player), additionalChoices: []),
            proposer: player,
            abilityInstructions: [.draw(count: 1)]
        )

        #expect(log.state().abilityOutcomeSummaries.isEmpty)
    }

    // MARK: - Correction

    /// The camera called it a Play; it was a Draw. Amending the entry
    /// re-derives everything after it.
    @Test("Correcting an entry changes the board it produces")
    func correctionRederives() {
        let (start, player, _) = fixture()
        var log = GameEventLog(initialState: start)
        let entry = log.record(action: .draw(count: 1), proposer: player)
        log.record(action: .draw(count: 1), proposer: player)

        let corrected = log.correcting(entry.id, action: .draw(count: 3))

        let handAtStart = start.zones[player]?.hand.count ?? 0
        #expect(log.state().zones[player]?.hand.count == handAtStart + 2)
        #expect(corrected.state().zones[player]?.hand.count == handAtStart + 4)
    }

    /// A correction returns a new log, so a caller can show the corrected
    /// board before committing to it.
    @Test("Correcting leaves the original log untouched")
    func correctionIsNonDestructive() {
        let (start, player, _) = fixture()
        var log = GameEventLog(initialState: start)
        let entry = log.record(action: .draw(count: 1), proposer: player)

        _ = log.correcting(entry.id, action: .draw(count: 5))

        #expect(log.entries.count == 1)
        #expect(log.state().zones[player]?.hand.count == (start.zones[player]?.hand.count ?? 0) + 1)
    }

    @Test("An entry can be struck out entirely — the camera saw a move that never happened")
    func removalRederives() {
        let (start, player, _) = fixture()
        var log = GameEventLog(initialState: start)
        let entry = log.record(action: .draw(count: 1), proposer: player)
        log.record(action: .draw(count: 1), proposer: player)

        let corrected = log.removing(entry.id)

        #expect(corrected.entries.count == 1)
        #expect(corrected.state().zones[player]?.hand.count == (start.zones[player]?.hand.count ?? 0) + 1)
    }

    /// Ids are the caller's handle on a moment. Renumbering after a removal
    /// would silently repoint every id anyone still holds.
    @Test("Removing an entry leaves a gap rather than renumbering")
    func idsAreStable() {
        let (start, player, _) = fixture()
        var log = GameEventLog(initialState: start)
        let first = log.record(action: .draw(count: 1), proposer: player)
        let second = log.record(action: .draw(count: 1), proposer: player)
        let third = log.record(action: .draw(count: 1), proposer: player)

        let corrected = log.removing(second.id)

        #expect(corrected.entries.map(\.id) == [first.id, third.id])
        #expect(third.id == 3, "the survivor keeps its original number")
    }

    @Test("Correcting an id the log doesn't have changes nothing")
    func unknownIDIsIgnored() {
        let (start, player, _) = fixture()
        var log = GameEventLog(initialState: start)
        log.record(action: .draw(count: 1), proposer: player)

        #expect(log.correcting(999, action: .draw(count: 9)).entries.count == 1)
        #expect(log.removing(999).entries.count == 1)
    }
}

/// The contract that actually matters: what the engine *did* and what the log
/// *replays* have to be the same board.
///
/// The tests above drive the log directly, so they can only prove it is
/// consistent with itself. This drives `GameEngine.process` — validator,
/// applier, effects, Cleanup, the lot — and then replays the log the engine
/// recorded on the way through. If `process` ever mutates state by a route
/// the log doesn't capture, this is what notices.
@Suite("Event log matches the live engine")
struct EventLogFidelityTests {

    private func session() -> (GameEngine, GameStateStore, PlayerID, ObjectID) {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()

        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell-under-test"),
            owner: playerA,
            name: "Spell Under Test",
            type: .spell,
            cost: Cost()
        )
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.mainDeck = (0..<6).map { index in
            MainDeckCard(
                definitionID: CardDefID(rawValue: "deck-\(index)"),
                owner: playerA,
                name: "Deck Card \(index)",
                type: .spell,
                cost: Cost()
            )
        }

        let store = GameStateStore(initialState: state)
        let translator = FixedActionTranslator(
            action: .play(card: card.id, destination: .base(playerA), additionalChoices: [])
        )
        return (GameEngine(store: store, observer: NeverObserving(), translator: translator), store, playerA, card.id)
    }

    private func playEvent(for player: PlayerID) -> ObservedTableEvent {
        ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: player, location: .base(player), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )
    }

    @Test("Replaying the engine's own log reproduces the engine's own board")
    func replayMatchesTheEngine() async {
        let (engine, store, player, _) = session()

        let instruction = await engine.process(playEvent(for: player))
        guard case .actionAccepted = instruction else {
            Issue.record("expected the play to be accepted, got \(instruction)")
            return
        }

        let live = await store.currentState
        guard let log = await engine.eventLog else {
            Issue.record("an accepted action should have been logged")
            return
        }
        let replayed = log.state()

        #expect(log.count == 1)
        #expect(replayed.zones[player]?.hand.count == live.zones[player]?.hand.count, "hand")
        #expect(replayed.zones[player]?.mainDeck.count == live.zones[player]?.mainDeck.count, "deck")
        #expect(replayed.units.count == live.units.count, "units")
        #expect(replayed.runes.count == live.runes.count, "runes")
        #expect(replayed.zones[player]?.runePool.energy == live.zones[player]?.runePool.energy, "energy")
    }

    /// A rejected action changes nothing, so it must leave no trace — a log
    /// that recorded attempts would replay a board that never existed.
    @Test("A rejected action is not logged")
    func rejectionsAreNotRecorded() async {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        // No such card in hand, so `.play` fails validation.
        state.zones[playerA]?.hand = []
        let store = GameStateStore(initialState: state)
        let engine = GameEngine(
            store: store,
            observer: NeverObserving(),
            translator: FixedActionTranslator(
                action: .play(card: ObjectID(), destination: .base(playerA), additionalChoices: [])
            )
        )

        _ = await engine.process(playEvent(for: playerA))

        let log = await engine.eventLog
        #expect(log == nil || log?.isEmpty == true, "a rejected action left a record")
    }
}
