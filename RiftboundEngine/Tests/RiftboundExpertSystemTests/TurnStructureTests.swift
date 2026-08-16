import Testing
@testable import RiftboundExpertSystem

/// Rule 514–517: the fixed part of a turn, and the boundary where it stops
/// being fixed.
///
/// The shape being pinned down here is that a Riftbound turn has exactly
/// one rigid prefix — Awaken → Beginning → Channel → Draw (515) — and after
/// that the Action Phase "has no defined structure" (516.2). There is no
/// Action → Showdown → End sequence: a Showdown is something a Move causes
/// (516.5.b), and the player decides everything else, in any order, until
/// they end the turn (516.6).
struct TurnStructureTests {

    // MARK: - The fixed prefix (515)

    @Test("Start of Turn runs Awaken, Beginning, Channel, Draw in order and stops at the Action Phase")
    func startOfTurnRunsFourStepsThenStops() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.awaken))
        TestFixtures.stockRuneDeck([.fury, .fury, .fury], for: playerA, in: &state)
        state.zones[playerA]?.mainDeck = [TestFixtures.makeMainDeckCard(owner: playerA)]

        state = TurnSequencer.advance(state)
        #expect(state.phase == .startOfTurn(.beginning))
        state = TurnSequencer.advance(state)
        #expect(state.phase == .startOfTurn(.channel))
        state = TurnSequencer.advance(state)
        #expect(state.phase == .startOfTurn(.draw))
        state = TurnSequencer.advance(state)
        #expect(state.phase == .action)

        // 516.2: the Action Phase is where the sequencer stops. Advancing
        // again must not push the turn into some next structured step —
        // there isn't one. Only `.endTurn` leaves here (516.6).
        state = TurnSequencer.advance(state)
        #expect(state.phase == .action)
    }

    /// Rule 515.1: the Turn Player readies all Game Objects they control.
    /// Runes are Game Objects (154.1), so they ready too — that is what
    /// makes the Energy engine cycle rather than draining over a few turns.
    @Test("Awaken readies the turn player's units, gear and runes, but not the opponent's")
    func awakenReadiesOnlyTheTurnPlayersObjects() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.awaken))

        let ownUnit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), isExhausted: true)
        let opponentUnit = TestFixtures.makeUnit(owner: playerB, location: .base(playerB), isExhausted: true)
        state.units[ownUnit.id] = ownUnit
        state.units[opponentUnit.id] = opponentUnit

        let ownRunes = TestFixtures.channelRunes([.fury], for: playerA, exhausted: true, into: &state)
        let opponentRunes = TestFixtures.channelRunes([.calm], for: playerB, exhausted: true, into: &state)

        state = TurnSequencer.advance(state)

        #expect(state.units[ownUnit.id]?.isExhausted == false)
        #expect(state.runes[ownRunes[0]]?.isExhausted == false)
        // 515.1 is the *Turn Player's* Awaken — the opponent's objects stay
        // exhausted until their own turn comes around.
        #expect(state.units[opponentUnit.id]?.isExhausted == true)
        #expect(state.runes[opponentRunes[0]]?.isExhausted == true)
    }

    /// Rule 515.3.b: 2 Runes. They arrive on the board (606.1), **Ready**,
    /// and produce no Energy — Energy comes from Exhausting them (157.2.a).
    @Test("Channel Phase puts two ready runes on the board and no energy in the pool")
    func channelPhaseChannelsTwoRunesAndNoEnergy() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.channel))
        TestFixtures.stockRuneDeck([.fury, .calm, .mind], for: playerA, in: &state)

        state = TurnSequencer.advance(state)

        #expect(state.runes.values.filter { $0.controller == playerA }.count == 2)
        #expect(state.runes.values.allSatisfy { !$0.isExhausted })
        #expect(state.zones[playerA]?.runeDeck.count == 1)
        // The whole point: two Runes is not two Energy.
        #expect(state.zones[playerA]?.runePool.energy == 0)
    }

    /// Rule 645.7 (and 644.7): in 1v1 the player going **second** channels
    /// an extra Rune on their first Channel Phase.
    @Test("The player going second channels three runes on their first turn, two after that")
    func playerGoingSecondChannelsThreeOnTheirFirstTurn() {
        var (state, _, playerB, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.channel))
        state.turnPlayerIndex = 1
        TestFixtures.stockRuneDeck([.fury, .calm, .mind, .body, .chaos], for: playerB, in: &state)

        state = TurnSequencer.advance(state)
        #expect(state.runes.values.filter { $0.controller == playerB }.count == 3)

        state.phase = .startOfTurn(.channel)
        state = TurnSequencer.advance(state)
        #expect(state.runes.values.filter { $0.controller == playerB }.count == 5)
    }

    /// Rule 515.4.d/160: "every player's Rune Pool empties at the end of
    /// each player's draw phase" — every player's, not just the Turn
    /// Player's, so Power banked by an opponent is lost here too.
    @Test("Draw Phase draws one card and empties every player's rune pool")
    func drawPhaseDrawsOneAndEmptiesAllRunePools() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.draw))
        state.zones[playerA]?.mainDeck = [
            TestFixtures.makeMainDeckCard(owner: playerA, name: "Top"),
            TestFixtures.makeMainDeckCard(owner: playerA, name: "Next")
        ]
        state.zones[playerA]?.runePool = RunePool(energy: 3, power: [.domain(.fury)])
        state.zones[playerB]?.runePool = RunePool(energy: 2, power: [.domain(.calm)])

        state = TurnSequencer.advance(state)

        #expect(state.zones[playerA]?.hand.count == 1)
        #expect(state.zones[playerA]?.hand.first?.name == "Top")
        #expect(state.zones[playerA]?.mainDeck.count == 1)
        #expect(state.zones[playerA]?.runePool == .empty)
        #expect(state.zones[playerB]?.runePool == .empty)
        #expect(state.phase == .action)
    }

    /// 645.7 gives the two-player modes **only** the extra-Rune clause. The
    /// "player going first doesn't draw" rule is 646.7/647.7/648.7, which
    /// are the 3- and 4-player modes. Pinning this because generalizing it
    /// to 1v1 is the obvious wrong move — it reads like a fairness rule
    /// that ought to apply everywhere, and it doesn't.
    @Test("In 1v1 the player going first does draw on turn one")
    func firstPlayerDrawsOnTurnOneInHeadsUp() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.channel))
        TestFixtures.stockRuneDeck([.fury, .calm], for: playerA, in: &state)
        state.zones[playerA]?.mainDeck = [TestFixtures.makeMainDeckCard(owner: playerA)]

        state = TurnSequencer.advance(state)   // Channel — marks turn 1 complete
        state = TurnSequencer.advance(state)   // Draw

        #expect(state.zones[playerA]?.hand.count == 1)
    }

    // MARK: - The free-form part (516.2)

    /// The user-facing claim this suite exists to guarantee: after ABCD,
    /// nothing is sequenced. A player may move a unit, then play a card,
    /// then move another unit, in whatever order they like, and the engine
    /// must not require them to have "entered" anything first.
    @Test("The Action Phase imposes no order on moves and plays")
    func actionPhaseAcceptsMovesAndPlaysInAnyOrder() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()

        let firstUnit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        let secondUnit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[firstUnit.id] = firstUnit
        state.units[secondUnit.id] = secondUnit

        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell"), owner: playerA,
            name: "Free Spell", type: .spell
        )
        state.zones[playerA]?.hand.append(card)

        // Move, then play, then move again — no phase advance in between.
        #expect(LegalityValidator.validate(
            .standardMove(units: [firstUnit.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        ).isSuccess)

        #expect(LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state, proposedBy: playerA
        ).isSuccess)

        #expect(LegalityValidator.validate(
            .standardMove(units: [secondUnit.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        ).isSuccess)
    }

    /// Rule 516.1: the Action Phase begins only "when all steps of the
    /// Start of Turn have been completed." A card played during Channel
    /// isn't early — it's outside the turn's structure entirely, and the
    /// player needs telling so before they've paid for it.
    @Test("Playing a card before the Action Phase is rejected")
    func playIsRejectedBeforeTheActionPhase() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.channel))
        let card = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell"), owner: playerA,
            name: "Too Early", type: .spell
        )
        state.zones[playerA]?.hand.append(card)

        let result = LegalityValidator.validate(
            .play(card: card.id, destination: .none, additionalChoices: []),
            in: state, proposedBy: playerA
        )

        #expect(result.failureValue == .notActionPhase(.startOfTurn(.channel)))
    }

    // MARK: - End of Turn (517)

    /// Rule 517.2/517.5: damage clears, pools empty, and the Turn Player
    /// becomes the next player in Turn Order — whose own Start of Turn then
    /// runs, because 515 grants nobody a window between those steps.
    @Test("Ending a turn clears damage, empties pools, and hands over to the next player")
    func endTurnCleansUpAndHandsOver() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var damaged = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        damaged.damage = 2
        state.units[damaged.id] = damaged
        state.zones[playerA]?.runePool = RunePool(energy: 4)
        TestFixtures.stockRuneDeck([.fury, .calm], for: playerB, in: &state)
        state.zones[playerB]?.mainDeck = [TestFixtures.makeMainDeckCard(owner: playerB)]

        GameActionApplier.apply(.endTurn, to: &state, proposedBy: playerA)

        #expect(state.units[damaged.id]?.damage == 0)        // 517.2.a
        #expect(state.zones[playerA]?.runePool == .empty)     // 517.2.c
        #expect(state.turnPlayer == playerB)                  // 517.5
        // The incoming player's fixed prefix ran through to their Action
        // Phase — they channeled and drew without anyone asking.
        #expect(state.phase == .action)
        #expect(state.runes.values.filter { $0.controller == playerB }.count == 2)
    }

    /// Rule 631: "once per Battlefield per turn" needs the ledger cleared
    /// when the turn changes, or a Battlefield held on turn one can never
    /// score again.
    @Test("A new turn makes every battlefield scoreable again")
    func endTurnClearsTheScoredThisTurnLedger() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.battlefieldControl[battlefieldID]?.scoredThisTurnBy = [playerA]
        TestFixtures.stockRuneDeck([.fury, .calm], for: playerB, in: &state)

        GameActionApplier.apply(.endTurn, to: &state, proposedBy: playerA)

        #expect(state.battlefieldControl[battlefieldID]?.scoredThisTurnBy.isEmpty == true)
    }

    /// Rule 516.5: Showdowns happen as a result of Action Phase actions.
    /// `Cleanup` also runs from the End of Turn's Cleanup Step (517.3), so
    /// without a phase guard a Battlefield still Contested at end of turn
    /// opened a Showdown *after* the turn was over — and then handed that
    /// half-started Showdown to the next player along with their turn.
    @Test("Ending a turn does not open a Showdown for the incoming player")
    func endTurnDoesNotOpenAShowdown() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        // Two controllers at one Battlefield: exactly what Cleanup 526
        // reacts to, left standing as the turn ends.
        let unitA = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let unitB = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        state.units[unitA.id] = unitA
        state.units[unitB.id] = unitB
        state.battlefieldControl[battlefieldID]?.isContested = true
        state.battlefieldControl[battlefieldID]?.contestedBy = playerA
        TestFixtures.stockRuneDeck([.fury, .calm], for: playerB, in: &state)

        GameActionApplier.apply(.endTurn, to: &state, proposedBy: playerA)

        #expect(state.turnPlayer == playerB)
        guard case .neutralOpen = state.turnState else {
            Issue.record("The incoming player inherited a Showdown: \(state.turnState)")
            return
        }
    }

    /// Rule 516.6: ending the turn is the Turn Player's declaration, and
    /// only from the Action Phase — there's nothing to end before it.
    @Test("Ending the turn is rejected outside the Action Phase")
    func endTurnRejectedOutsideActionPhase() {
        let (state, playerA, _, _) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.beginning))

        let result = LegalityValidator.validate(.endTurn, in: state, proposedBy: playerA)

        #expect(result.failureValue == .notActionPhase(.startOfTurn(.beginning)))
    }
}
