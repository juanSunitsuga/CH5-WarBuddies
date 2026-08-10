import Testing
@testable import RiftboundExpertSystem

struct GameEngineTests {

    /// Worked scenario from rules 181.3.a, 613.1, 525, 549, 550.2: Player A
    /// Standard Moves a Unit into a Battlefield that is Uncontrolled and has
    /// no Units present from any other player. That Move applies Contested
    /// status to the Battlefield (181.3.a — A doesn't currently Control it),
    /// and because it now has no opposing Units present, Cleanup opens a
    /// standalone Showdown there (613.1/525) rather than triggering Combat.
    /// Player A, having applied Contested status, gains Focus (549); since
    /// this Showdown isn't part of Combat, all players become Relevant
    /// (550.2).
    @Test("Standard Move into an uncontrolled, empty battlefield opens a standalone Showdown")
    func standardMoveTriggersStandaloneShowdown() async {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        let store = GameStateStore(initialState: state)
        let action = GameAction.standardMove(units: [unit.id], destination: .battlefield(battlefieldID))
        let engine = GameEngine(
            store: store,
            observer: NeverObserving(),
            translator: FixedActionTranslator(action: action)
        )

        let event = ObservedTableEvent(
            kind: .cardMoved(
                from: TableRegion(owner: playerA, location: .base(playerA), isHandRegion: false),
                to: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)
            ),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.process(event)

        guard case .actionAccepted(let acceptedAction, _) = instruction else {
            Issue.record("Expected the Standard Move to be accepted, got \(instruction)")
            return
        }
        #expect(acceptedAction.isStandardMove)

        let finalState = await store.currentState

        // The unit actually moved and paid its exhaust cost (140.2, 610).
        #expect(finalState.units[unit.id]?.location == .battlefield(battlefieldID))
        #expect(finalState.units[unit.id]?.isExhausted == true)

        // The Battlefield became Contested, attributed to Player A (181.3.a).
        #expect(finalState.battlefieldControl[battlefieldID]?.isContested == true)
        #expect(finalState.battlefieldControl[battlefieldID]?.contestedBy == playerA)

        // A standalone Showdown opened, with Player A holding Focus and
        // both players Relevant.
        guard case .showdownOpen(let showdown) = finalState.turnState else {
            Issue.record("Expected turnState to be .showdownOpen, got \(finalState.turnState)")
            return
        }
        #expect(showdown.origin == .standalone(battlefield: battlefieldID))
        #expect(showdown.focusPlayer == playerA)
        #expect(showdown.relevantPlayers == Set([playerA, playerB]))
    }
}

private extension GameAction {
    var isStandardMove: Bool {
        if case .standardMove = self { return true }
        return false
    }
}
