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

    // MARK: - resolveDeferredPlay (deferred Play submission)

    /// `RiftboundVision.PendingPlay`'s reason to exist: a Play's real
    /// `observedExhaustedRuneCount` is only known once the app has watched
    /// payment settle, well after the landing event `process(_:)` would
    /// otherwise fire on. `resolveDeferredPlay` still asks the translator
    /// to classify the event — same as `process(_:)` would — and only
    /// patches the observed count onto whatever it comes back with.
    @Test("resolveDeferredPlay still asks the translator, and applies the Play it returns")
    func resolveDeferredPlayAppliesTranslatedCard() async {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let definitionID = CardDefID(rawValue: "card-Test Unit")
        let card = MainDeckCard(
            definitionID: definitionID,
            owner: playerA,
            name: "Test Unit",
            type: .unit(isChampion: false),
            cost: Cost(energy: 2, powerCost: 0, eligibleDomains: []),
            might: 3
        )
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 2

        let store = GameStateStore(initialState: state)
        let translatedAction = GameAction.play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [])
        let engine = GameEngine(store: store, observer: NeverObserving(), translator: FixedActionTranslator(action: translatedAction))
        let landingEvent = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.resolveDeferredPlay(
            for: landingEvent,
            observedExhaustedRuneCount: 2,
            proposedBy: playerA
        )

        guard case .actionAccepted = instruction else {
            Issue.record("Expected the Play to be accepted, got \(instruction)")
            return
        }
        let finalState = await store.currentState
        #expect(finalState.zones[playerA]?.hand.contains(where: { $0.definitionID == definitionID }) == false)
        #expect(finalState.units.values.contains { $0.cardDefinitionID == definitionID && $0.location == .battlefield(battlefieldID) })
    }

    /// 130.2: the whole point of threading the observed count through —
    /// a mismatch is caught exactly like it would be from `process(_:)`.
    @Test("resolveDeferredPlay rejects a Play whose observed Rune count doesn't match Energy cost")
    func resolveDeferredPlayRejectsMismatchedRuneCount() async {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let definitionID = CardDefID(rawValue: "card-Test Unit")
        let card = MainDeckCard(
            definitionID: definitionID,
            owner: playerA,
            name: "Test Unit",
            type: .unit(isChampion: false),
            cost: Cost(energy: 2, powerCost: 0, eligibleDomains: []),
            might: 3
        )
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 2

        let store = GameStateStore(initialState: state)
        let translatedAction = GameAction.play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [])
        let engine = GameEngine(store: store, observer: NeverObserving(), translator: FixedActionTranslator(action: translatedAction))
        let landingEvent = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.resolveDeferredPlay(
            for: landingEvent,
            observedExhaustedRuneCount: 1,
            proposedBy: playerA
        )

        guard case .actionRejected(_, let reason) = instruction else {
            Issue.record("Expected the Play to be rejected, got \(instruction)")
            return
        }
        #expect(reason == .exhaustedRuneCountMismatch(required: 2, observed: 1))
        let finalState = await store.currentState
        #expect(finalState.zones[playerA]?.hand.contains(where: { $0.definitionID == definitionID }) == true)
    }

    /// The translator is still the authority on what the event means — if
    /// it can't resolve the card at all (e.g. it left the hand some other
    /// way between landing and settlement), this reports the same outcome
    /// `process(_:)` would, rather than forcing a Play through.
    @Test("resolveDeferredPlay reports unrecognized when the translator can't resolve the event")
    func resolveDeferredPlayReportsUnrecognizedWhenUntranslatable() async {
        let (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let store = GameStateStore(initialState: state)
        let engine = GameEngine(store: store, observer: NeverObserving(), translator: FixedActionTranslator(action: nil))
        let landingEvent = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.resolveDeferredPlay(
            for: landingEvent,
            observedExhaustedRuneCount: 0,
            proposedBy: playerA
        )

        guard case .unrecognizedEvent = instruction else {
            Issue.record("Expected unrecognizedEvent, got \(instruction)")
            return
        }
    }

    /// If the translator decides this event isn't a Play after all,
    /// `resolveDeferredPlay` trusts that instead of forcing one — the
    /// observed Rune count only makes sense attached to a Play.
    @Test("resolveDeferredPlay defers to a non-Play action the translator returns")
    func resolveDeferredPlayHonorsNonPlayTranslation() async {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        let store = GameStateStore(initialState: state)
        let moveAction = GameAction.standardMove(units: [unit.id], destination: .battlefield(battlefieldID))
        let engine = GameEngine(store: store, observer: NeverObserving(), translator: FixedActionTranslator(action: moveAction))
        let landingEvent = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.resolveDeferredPlay(
            for: landingEvent,
            observedExhaustedRuneCount: 99,
            proposedBy: playerA
        )

        guard case .actionAccepted(let acceptedAction, _) = instruction else {
            Issue.record("Expected the Standard Move to be accepted, got \(instruction)")
            return
        }
        #expect(acceptedAction.isStandardMove)
    }

    // MARK: - Ability resolution end to end

    /// The full loop this session's work exists for: a Unit is Played,
    /// `GameActionApplier` queues its ability, `GameEngine` asks the
    /// translator to parse it, and `EffectExecutor` actually runs the
    /// result — a card's printed text changing `GameState`, not just
    /// being recognized. Mirrors real cards like "Lecturing Yordle"
    /// ("When you play me, draw 1").
    @Test("Playing a Unit resolves its parsed ability and reports it in followUp")
    func playingAUnitResolvesItsAbility() async {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "card-Test Unit"),
            owner: playerA,
            name: "Test Unit",
            type: .unit(isChampion: false),
            cost: Cost(energy: 0, powerCost: 0, eligibleDomains: []),
            might: 3
        )
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.mainDeck = [TestFixtures.makeMainDeckCard(owner: playerA, name: "Top Deck Card")]
        let startingHandCount = state.zones[playerA]?.hand.count ?? 0

        let store = GameStateStore(initialState: state)
        let playAction = GameAction.play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [])
        let translator = FixedActionTranslator(action: playAction, abilityInstructions: [.draw(count: 1)])
        let engine = GameEngine(store: store, observer: NeverObserving(), translator: translator)
        let event = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.process(event)

        guard case .actionAccepted(_, let followUp) = instruction else {
            Issue.record("Expected the Play to be accepted, got \(instruction)")
            return
        }
        #expect(followUp?.description.contains("Drew 1 card") == true)
        let finalState = await store.currentState
        // -1 for the Unit leaving Hand, +1 for the ability's own Draw.
        #expect(finalState.zones[playerA]?.hand.count == startingHandCount)
        #expect(finalState.zones[playerA]?.mainDeck.isEmpty == true)
    }

    /// Same loop, but the target is one the proposer already declared via
    /// `additionalChoices` (559.3) rather than a targetless effect —
    /// confirms `AbilityResolution.targets` actually reaches
    /// `EffectExecutor` from the original `GameAction.play`.
    @Test("Playing a Unit whose ability targets an already-declared unit damages that unit")
    func playingAUnitResolvesATargetedAbility() async {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "card-Test Unit"),
            owner: playerA,
            name: "Test Unit",
            type: .unit(isChampion: false),
            cost: Cost(energy: 0, powerCost: 0, eligibleDomains: []),
            might: 3
        )
        state.zones[playerA]?.hand.append(card)
        let victim = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        state.units[victim.id] = victim

        let store = GameStateStore(initialState: state)
        let playAction = GameAction.play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [victim.id])
        let translator = FixedActionTranslator(action: playAction, abilityInstructions: [.dealDamage(amount: 4, targets: .chosenUnit())])
        let engine = GameEngine(store: store, observer: NeverObserving(), translator: translator)
        let event = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        _ = await engine.process(event)

        let finalState = await store.currentState
        #expect(finalState.units[victim.id]?.damage == 4)
    }
}

private extension GameAction {
    var isStandardMove: Bool {
        if case .standardMove = self { return true }
        return false
    }
}
