import Testing
@testable import RiftboundExpertSystem

/// Rule 555–563: Playing a Card. Covers both halves — `LegalityValidator`'s
/// rejection reasons and `GameActionApplier`'s state transition — plus one
/// end-to-end pass through `GameEngine.process` so the Validator → Applier →
/// Cleanup sequence is exercised as a whole.
struct PlayActionTests {

    private static func handCard(
        owner: PlayerID,
        name: String = "Test Unit Card",
        type: MainDeckCardType = .unit(isChampion: false),
        energy: Int = 0,
        might: Int? = 3
    ) -> MainDeckCard {
        MainDeckCard(
            definitionID: CardDefID(rawValue: "card-\(name)"),
            owner: owner,
            name: name,
            type: type,
            cost: Cost(energy: energy),
            might: might
        )
    }

    // MARK: - Legality (555–561)

    /// Rule 559.2: a Unit is Played to a chosen Location the player
    /// controls. With a readied Rune Pool covering its cost (560–561) and a
    /// Battlefield free of other controllers, this is legal.
    @Test("Playing a Unit from hand to an empty battlefield is legal")
    func legalPlayUnitToBattlefield() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 2)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 2

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// Rule 555.1/558: Play removes the card from the zone it's played
    /// from — a card that isn't in hand can't be played out of it.
    @Test("Playing a card that isn't in hand is rejected")
    func rejectsCardNotInHand() {
        let (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let strayID = ObjectID()

        let result = LegalityValidator.validate(
            .play(card: strayID, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .cardNotInHand(strayID))
    }

    /// Rule 559.2: "For Units, choose a Location the player Controls on the
    /// Board where that Unit will be placed upon being Played." `.none` is
    /// only meaningful for Spells/abilities, which have no board form.
    @Test("Playing a Unit with no destination is rejected (rule 559.2)")
    func rejectsUnitWithoutDestination() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA)
        state.zones[playerA]?.hand.append(card)

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .invalidPlayDestination(.none))
    }

    /// Rule 560–561: the card's Energy cost must be payable out of the
    /// player's Rune Pool at the time it's Played.
    @Test("Playing a card the player can't pay for is rejected (rule 560-561)")
    func rejectsUnaffordableCard() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 5)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 1

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .insufficientEnergy(required: 5, available: 1))
    }

    // MARK: - Application (563)

    /// Rule 558 + 561 + 563.1.c: the card leaves the Hand, its Energy cost
    /// is paid out of the Rune Pool, and the Unit enters the Board
    /// *exhausted* at the chosen Location.
    @Test("Applying a Unit play moves it from hand to the board, exhausted, and pays its cost")
    func applyPlayUnitEntersBoardExhausted() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 2, might: 4)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 3

        GameActionApplier.apply(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            to: &state,
            proposedBy: playerA
        )

        #expect(state.zones[playerA]?.hand.isEmpty == true)          // 558
        #expect(state.zones[playerA]?.runePool.energy == 1)          // 561
        let unit = state.units.values.first { $0.cardDefinitionID == card.definitionID }
        #expect(unit != nil)
        #expect(unit?.location == .battlefield(battlefieldID))       // 559.2
        #expect(unit?.isExhausted == true)                           // 563.1.c
        #expect(unit?.baseMight == 4)
    }

    /// Rule 556.2/563.2: a Spell has no board form — it produces its effect
    /// and goes to the Trash. (Its effect isn't executed yet; ability
    /// parsing returns `[]` until the Effects pipeline is built.)
    @Test("Applying a Spell play sends it to the trash rather than the board")
    func applyPlaySpellGoesToTrash() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, name: "Test Spell", type: .spell, might: nil)
        state.zones[playerA]?.hand.append(card)

        GameActionApplier.apply(
            .play(card: card.id, destination: .none, additionalChoices: []),
            to: &state,
            proposedBy: playerA
        )

        #expect(state.zones[playerA]?.hand.isEmpty == true)
        #expect(state.zones[playerA]?.trash.count == 1)
        #expect(state.units.isEmpty)
    }

    /// Rule 563.1.d + 144.2: Gear always enters at the player's Base, Ready
    /// — never exhausted, never at a Battlefield.
    @Test("Applying a Gear play puts it on the board ready (rule 563.1.d)")
    func applyPlayGearEntersReady() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, name: "Test Gear", type: .gear, might: nil)
        state.zones[playerA]?.hand.append(card)

        GameActionApplier.apply(
            .play(card: card.id, destination: .base(playerA), additionalChoices: []),
            to: &state,
            proposedBy: playerA
        )

        let gear = state.gear.values.first { $0.cardDefinitionID == card.definitionID }
        #expect(gear != nil)
        #expect(gear?.isExhausted == false)
        #expect(state.units.isEmpty)
    }

    // MARK: - End to end (GameEngine)

    /// The whole path the live app now uses: an observed table event is
    /// translated to a `.play`, validated, applied, and Cleanup run — all
    /// inside `GameEngine.process`, with the result surfaced as a
    /// `PlayerInstruction` the UI can render.
    @Test("GameEngine accepts a play event end to end and updates the store")
    func engineAcceptsPlayEndToEnd() async {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 1)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 1

        let store = GameStateStore(initialState: state)
        let action = GameAction.play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [])
        let engine = GameEngine(
            store: store,
            observer: NeverObserving(),
            translator: FixedActionTranslator(action: action)
        )

        let event = ObservedTableEvent(
            kind: .cardAppeared(region: TableRegion(owner: playerA, location: .battlefield(battlefieldID), isHandRegion: false)),
            card: nil,
            observedAt: 0
        )

        let instruction = await engine.process(event)

        guard case .actionAccepted = instruction else {
            Issue.record("Expected the Play to be accepted, got \(instruction)")
            return
        }

        let finalState = await store.currentState
        #expect(finalState.zones[playerA]?.hand.isEmpty == true)
        #expect(finalState.units.values.contains { $0.cardDefinitionID == card.definitionID })
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
