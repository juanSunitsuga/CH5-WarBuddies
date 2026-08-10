import Testing
@testable import RiftboundExpertSystem

/// Rule 589.2: Limited Actions (Draw among them) are "only ever performed
/// when a rule or effect explicitly calls for it" — never player-initiated
/// at will. These tests cover the exact failure mode that motivated this:
/// a played card has a "when I enter play, draw a card" trigger, but the
/// physical player draws *before* that trigger has actually resolved.
/// `GameState.pendingLimitedActions` is what the eventual Chain/Effect
/// resolution pipeline will populate via `authorize(_:for:)`; until that
/// exists, tests call it directly to simulate "the trigger just resolved."
struct LimitedActionAuthorizationTests {

    @Test("Draw is illegal when nothing has authorized it (rule 589.2)")
    func unauthorizedDrawIsRejected() {
        let (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()

        let result = LegalityValidator.validate(.draw(count: 1), in: state, proposedBy: playerA)

        #expect(result.failureValue == .limitedActionNotAuthorized(.draw(count: 1)))
    }

    @Test("Draw is legal once a resolved effect has authorized it, and is consumed by applying it")
    func authorizedDrawSucceedsAndIsConsumed() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        state.zones[playerA]!.mainDeck = [TestFixtures.makeMainDeckCard(owner: playerA)]

        // Simulate: the played card's "when I enter play, draw a card"
        // Triggered Ability just resolved.
        state.authorize(.draw(count: 1), for: playerA)

        #expect(LegalityValidator.validate(.draw(count: 1), in: state, proposedBy: playerA).isSuccess)

        GameActionApplier.apply(.draw(count: 1), to: &state, proposedBy: playerA)

        #expect(state.zones[playerA]?.hand.count == 1)
        #expect(state.zones[playerA]?.mainDeck.isEmpty == true)

        // The authorization was a one-time grant — a second physical draw
        // is not covered by it.
        #expect(state.pendingLimitedActions[playerA]?.isEmpty ?? true)
        #expect(
            LegalityValidator.validate(.draw(count: 1), in: state, proposedBy: playerA).failureValue
                == .limitedActionNotAuthorized(.draw(count: 1))
        )
    }

    /// End-to-end via `GameEngine`, mirroring the physical scenario: the
    /// player draws before their played card's trigger has resolved. The
    /// draw must be rejected, and — critically — `GameState` must come back
    /// completely unchanged, since `GameEngine.process` validates before it
    /// ever calls `store.mutate`. That's what makes "tell the player to put
    /// the card back" correct: the engine's model never believed the draw
    /// happened, so there's nothing to roll back on the model side.
    @Test("A premature draw is rejected end-to-end and leaves GameState untouched")
    func prematureDrawLeavesStateUntouched() async {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let deckCard = TestFixtures.makeMainDeckCard(owner: playerA)
        state.zones[playerA]!.mainDeck = [deckCard]
        // Note: no `state.authorize(...)` call — the enter-play trigger
        // has NOT resolved yet, same as the player jumping the gun.

        let store = GameStateStore(initialState: state)
        let engine = GameEngine(
            store: store,
            observer: NeverObserving(),
            translator: FixedActionTranslator(action: .draw(count: 1))
        )

        let event = ObservedTableEvent(
            kind: .cardMoved(
                from: TableRegion(owner: playerA, location: nil, isHandRegion: false),
                to: TableRegion(owner: playerA, location: nil, isHandRegion: true)
            ),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.process(event)

        guard case .actionRejected(_, let reason) = instruction else {
            Issue.record("Expected the premature draw to be rejected, got \(instruction)")
            return
        }
        #expect(reason == .limitedActionNotAuthorized(.draw(count: 1)))

        let finalState = await store.currentState
        #expect(finalState.zones[playerA]?.mainDeck.count == 1)
        #expect(finalState.zones[playerA]?.hand.isEmpty == true)
    }
}

private extension Result where Success == Void, Failure == LegalityValidator.Failure {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failureValue: LegalityValidator.Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
