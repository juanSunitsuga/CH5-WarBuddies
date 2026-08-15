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
        powerCost: Int = 0,
        eligibleDomains: [Domain] = [],
        might: Int? = 3,
        keywords: [Keyword] = []
    ) -> MainDeckCard {
        MainDeckCard(
            definitionID: CardDefID(rawValue: "card-\(name)"),
            owner: owner,
            name: name,
            type: type,
            cost: Cost(energy: energy, powerCost: powerCost, eligibleDomains: eligibleDomains),
            might: might,
            keywords: keywords
        )
    }

    /// A throwaway single-item Chain, just to give `GameState.turnState`
    /// something concrete to be Closed around — its content doesn't matter
    /// for these tests, only that a Chain exists and who its `activePlayer`
    /// is (512.2.c: that's who has Priority while it does).
    private static func chain(activePlayer: PlayerID, relevantPlayers: Set<PlayerID>) -> Chain {
        Chain(
            firstItem: .activatedAbility(source: ObjectID(), effectID: EffectID(), targets: []),
            activePlayer: activePlayer,
            relevantPlayers: relevantPlayers
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

    // MARK: - Action/Reaction windows (508.1.a/509.1.a)

    /// 509.1.a: while the turn is Neutral Closed (a Chain exists, no
    /// Showdown), only Reaction-tagged cards may respond.
    @Test("A Reaction card is legal while the turn is Neutral Closed")
    func reactionCardLegalWhenNeutralClosed() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, type: .spell, might: nil, keywords: [.reaction])
        state.zones[playerA]?.hand.append(card)
        state.turnState = .neutralClosed(Self.chain(activePlayer: playerA, relevantPlayers: [playerA, playerB]))

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// Same window, but the card carries no Reaction tag — the normal
    /// "just play a card" case is only legal in Neutral Open.
    @Test("A plain card is rejected while the turn is Neutral Closed")
    func plainCardRejectedWhenNeutralClosed() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, type: .spell, might: nil)
        state.zones[playerA]?.hand.append(card)
        state.turnState = .neutralClosed(Self.chain(activePlayer: playerA, relevantPlayers: [playerA, playerB]))

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .reactionRequired)
    }

    /// 512.2.c: Priority while Closed belongs to the Chain's `activePlayer`
    /// specifically — even a Reaction card from someone else is rejected,
    /// on priority grounds rather than the card's own tag.
    @Test("Even a Reaction card is rejected from a player without Priority")
    func reactionCardRejectedWithoutPriority() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerB, type: .spell, might: nil, keywords: [.reaction])
        state.zones[playerB]?.hand.append(card)
        state.turnState = .neutralClosed(Self.chain(activePlayer: playerA, relevantPlayers: [playerA, playerB]))

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerB
        )

        #expect(result.failureValue == .notPlayersPriority)
    }

    /// 508.1.a: while a Showdown is Open (no Chain yet), Action-tagged
    /// cards may open its Chain.
    @Test("An Action card is legal while a Showdown is Open")
    func actionCardLegalWhenShowdownOpen() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, type: .spell, might: nil, keywords: [.action])
        state.zones[playerA]?.hand.append(card)
        state.turnState = .showdownOpen(Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: playerA,
            relevantPlayers: [playerA, playerB]
        ))

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// Same window also accepts Reaction-tagged cards (508.1.a lists both).
    @Test("A Reaction card is also legal while a Showdown is Open")
    func reactionCardLegalWhenShowdownOpen() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, type: .spell, might: nil, keywords: [.reaction])
        state.zones[playerA]?.hand.append(card)
        state.turnState = .showdownOpen(Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: playerA,
            relevantPlayers: [playerA, playerB]
        ))

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// A plain, untagged card can't open a Showdown's Chain either.
    @Test("A plain card is rejected while a Showdown is Open")
    func plainCardRejectedWhenShowdownOpen() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, type: .spell, might: nil)
        state.zones[playerA]?.hand.append(card)
        state.turnState = .showdownOpen(Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: playerA,
            relevantPlayers: [playerA, playerB]
        ))

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .actionOrReactionRequired)
    }

    /// 510.4/509.1.a: Showdown Closed is the stricter gate — once a Chain
    /// exists *inside* the Showdown, only Reaction-tagged cards may
    /// respond, same as Neutral Closed; an Action-only card that was legal
    /// a moment ago (Showdown Open) is not legal here.
    @Test("Only a Reaction card is legal while a Showdown is Closed")
    func onlyReactionCardLegalWhenShowdownClosed() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let reactionCard = Self.handCard(owner: playerA, name: "Reaction Card", type: .spell, might: nil, keywords: [.reaction])
        let actionCard = Self.handCard(owner: playerA, name: "Action Card", type: .spell, might: nil, keywords: [.action])
        state.zones[playerA]?.hand.append(contentsOf: [reactionCard, actionCard])

        let showdown = Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: playerA,
            relevantPlayers: [playerA, playerB]
        )
        state.turnState = .showdownClosed(showdown, Self.chain(activePlayer: playerA, relevantPlayers: [playerA, playerB]))

        let reactionResult = LegalityValidator.validate(
            .play(card: reactionCard.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )
        #expect(reactionResult.isSuccess)

        let actionResult = LegalityValidator.validate(
            .play(card: actionCard.id, destination: .none, additionalChoices: []),
            in: state,
            proposedBy: playerA
        )
        #expect(actionResult.failureValue == .reactionRequired)
    }

    // MARK: - Observed exhausted-Rune count (130.2)

    /// Rule 130.2: Energy is paid by Exhausting Runes, so a Unit costing 3
    /// Energy should correspond to exactly 3 Runes physically Exhausted.
    /// Observing only 2 is rejected even though the abstract `RunePool`
    /// has the Energy to cover it — the physical count is what's actually
    /// wrong here, not the pool balance.
    @Test("Playing a card is rejected when the observed exhausted-Rune count is short")
    func rejectsShortExhaustedRuneCount() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 3)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 3

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [], observedExhaustedRuneCount: 2),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .exhaustedRuneCountMismatch(required: 3, observed: 2))
    }

    /// Same shortfall check, but for observing *too many* Exhausted Runes
    /// — 130.2 asks for exactly the cost, not "at least."
    @Test("Playing a card is rejected when the observed exhausted-Rune count is excessive")
    func rejectsExcessiveExhaustedRuneCount() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 3)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 3

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [], observedExhaustedRuneCount: 4),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .exhaustedRuneCountMismatch(required: 3, observed: 4))
    }

    /// A matching observed count is legal.
    @Test("Playing a card is legal when the observed exhausted-Rune count matches its cost")
    func acceptsMatchingExhaustedRuneCount() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 3)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 3

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: [], observedExhaustedRuneCount: 3),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// `nil` (no observation available) skips the check entirely — this is
    /// what every translator without live vision access proposes, and it
    /// must not be treated as "observed zero."
    @Test("Playing a card with no observed exhausted-Rune count skips the check")
    func nilObservedExhaustedRuneCountSkipsCheck() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, energy: 3)
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.energy = 3

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    // MARK: - Power cost (560–561/130.3)

    /// A single-Domain card requiring 2 Chaos is rejected if the player
    /// Recycled 2 Fury instead — the wrong Domain, not just the wrong
    /// count.
    @Test("Playing a card is rejected when the recycled Runes are the wrong Domain")
    func rejectsWrongDomainRecycle() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, powerCost: 2, eligibleDomains: [.chaos])
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.power = [.domain(.fury), .domain(.fury)]

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .insufficientPower(required: 2, available: 0))
    }

    /// Same card (2 Chaos required), but the player Recycled 1 Fury + 1
    /// Chaos — one matching entry isn't enough even though 2 Runes total
    /// were spent.
    @Test("Playing a card is rejected when only some recycled Runes match the required Domain")
    func rejectsPartiallyMatchingRecycle() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, powerCost: 2, eligibleDomains: [.chaos])
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.power = [.domain(.fury), .domain(.chaos)]

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .insufficientPower(required: 2, available: 1))
    }

    /// A dual-Domain card (Tibbers-style: power 2, domains [Fury, Chaos])
    /// accepts any combination from its listed Domains — one of each is
    /// exactly as legal as two of a single one.
    @Test("Playing a dual-Domain card accepts one Rune of each listed Domain")
    func acceptsOneOfEachEligibleDomain() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, powerCost: 2, eligibleDomains: [.fury, .chaos])
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.power = [.domain(.fury), .domain(.chaos)]

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// A Universal Power token (156.2.b) pays for any Domain.
    @Test("A Universal Power token satisfies any eligible Domain")
    func universalPowerSatisfiesAnyDomain() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, powerCost: 1, eligibleDomains: [.mind])
        state.zones[playerA]?.hand.append(card)
        state.zones[playerA]?.runePool.power = [.universal]

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    /// `applyRecycleRune` feeds `RunePool.power` and the cumulative
    /// `totalRunesRecycled` tally independently; a later `applyPlay`
    /// consumes only the matching entries from the pool, leaving
    /// non-matching ones (and the cumulative tally) untouched.
    @Test("Recycling then playing consumes only the matching power entries")
    func recycleThenPlayConsumesMatchingEntriesOnly() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, powerCost: 1, eligibleDomains: [.chaos])
        state.zones[playerA]?.hand.append(card)

        GameActionApplier.apply(.recycleRune(domain: .fury), to: &state, proposedBy: playerA)
        GameActionApplier.apply(.recycleRune(domain: .chaos), to: &state, proposedBy: playerA)

        #expect(state.zones[playerA]?.runePool.power == [.domain(.fury), .domain(.chaos)])
        #expect(state.totalRunesRecycled[playerA] == 2)

        GameActionApplier.apply(
            .play(card: card.id, destination: .battlefield(battlefieldID), additionalChoices: []),
            to: &state,
            proposedBy: playerA
        )

        // The Chaos entry paid for the card; the unrelated Fury entry is
        // still sitting in the pool, untouched.
        #expect(state.zones[playerA]?.runePool.power == [.domain(.fury)])
        // Consuming from the pool doesn't reverse the cumulative tally —
        // it's a historical record, not a live balance.
        #expect(state.totalRunesRecycled[playerA] == 2)
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

    /// Rule 556.2/563.2/534: a Spell has no board form and does not
    /// resolve immediately — it leaves the Hand right away (558) but
    /// becomes a Chain item, opening a Chain (Neutral Open → Neutral
    /// Closed) rather than landing straight in the Trash. It only reaches
    /// the Trash once the Chain resolves (both players Passing).
    @Test("Applying a Spell play opens a Chain instead of trashing it immediately")
    func applyPlaySpellOpensChain() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        let card = Self.handCard(owner: playerA, name: "Test Spell", type: .spell, might: nil)
        state.zones[playerA]?.hand.append(card)

        GameActionApplier.apply(
            .play(card: card.id, destination: .none, additionalChoices: []),
            to: &state,
            proposedBy: playerA
        )

        #expect(state.zones[playerA]?.hand.isEmpty == true)      // 558
        #expect(state.zones[playerA]?.trash.isEmpty == true)     // not yet — still on the Chain
        #expect(state.units.isEmpty)

        guard case .neutralClosed(let chain) = state.turnState else {
            Issue.record("Expected a Chain to have opened, got \(state.turnState)")
            return
        }
        #expect(chain.items.count == 1)
        #expect(chain.activePlayer == playerA)

        // Both players Pass — the Chain resolves its one item and closes.
        GameActionApplier.apply(.pass, to: &state, proposedBy: playerB)
        GameActionApplier.apply(.pass, to: &state, proposedBy: playerA)

        #expect(state.zones[playerA]?.trash.count == 1)
        guard case .neutralOpen = state.turnState else {
            Issue.record("Expected the Chain to have closed, got \(state.turnState)")
            return
        }
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
