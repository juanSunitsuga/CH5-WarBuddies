import Testing
@testable import RiftboundExpertSystem

/// Rules 511–513 and 545–553: Focus, and how a Showdown actually proceeds.
///
/// Focus is the permission to act during a Showdown Open state (513.1), and
/// it *moves*: the attacker gets it first (549), it passes to the next
/// Relevant Player when its holder passes (553.5), it passes again when a
/// Chain resolves inside the Showdown (552), and when everyone has passed
/// in sequence the Showdown ends (553.4.a).
///
/// Before this, `ChainResolver.pass` returned early on `.showdownOpen` and
/// did nothing at all — so Focus never moved and a Showdown nobody wanted
/// to act in simply never ended. The turn stopped dead, and no Conquer
/// could ever happen.
struct ShowdownFocusTests {

    private static func openShowdown(
        attacker: PlayerID,
        defender: PlayerID,
        battlefield: BattlefieldID
    ) -> Showdown {
        Showdown(
            origin: .combat(attacker: attacker, defender: defender, battlefield: battlefield),
            focusPlayer: attacker,          // 549
            relevantPlayers: [attacker, defender]   // 550.1
        )
    }

    /// 553.5: "Otherwise, Focus passes to the next Relevant Player in Turn
    /// Order." One pass out of two doesn't end anything.
    @Test("Passing during a Showdown hands Focus to the next relevant player")
    func passingHandsOverFocus() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.turnState = .showdownOpen(Self.openShowdown(attacker: playerA, defender: playerB, battlefield: battlefieldID))

        let outcome = ChainResolver.pass(by: playerA, in: &state)

        #expect(outcome.isRecordedOnly)
        guard case .showdownOpen(let showdown) = state.turnState else {
            Issue.record("Expected the Showdown to still be open, got \(state.turnState)")
            return
        }
        #expect(showdown.focusPlayer == playerB)
    }

    /// 512.2.b/513.2: "A player who gains Focus also gains Priority." Once
    /// Focus has moved, the validator must agree that it's the new player's
    /// window — otherwise Focus would be a label with no consequence.
    @Test("Gaining Focus gains Priority")
    func focusCarriesPriority() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.turnState = .showdownOpen(Self.openShowdown(attacker: playerA, defender: playerB, battlefield: battlefieldID))
        ChainResolver.pass(by: playerA, in: &state)

        #expect(LegalityValidator.validate(.pass, in: state, proposedBy: playerB).isSuccess)
        #expect(LegalityValidator.validate(.pass, in: state, proposedBy: playerA).failureValue == .notPlayersPriority)
    }

    /// 553.4.a: "If all Relevant Players have passed once in sequence, the
    /// Showdown ends."
    @Test("A Showdown ends once every relevant player has passed in sequence")
    func showdownEndsWhenEveryoneHasPassed() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.turnState = .showdownOpen(Self.openShowdown(attacker: playerA, defender: playerB, battlefield: battlefieldID))

        ChainResolver.pass(by: playerA, in: &state)
        let outcome = ChainResolver.pass(by: playerB, in: &state)

        #expect(outcome.endedShowdown != nil)
        guard case .neutralOpen = state.turnState else {
            Issue.record("Expected Neutral Open after the Showdown ended, got \(state.turnState)")
            return
        }
    }

    /// 552: "When the last item on the chain resolves during a Showdown,
    /// Focus passes, and the next Relevant Player gains both Focus and
    /// Priority." A resolving item also breaks the run of passes — 553.4.a
    /// counts passes *in sequence*, and something just happened.
    @Test("Resolving the last chain item passes Focus and clears the pass sequence")
    func chainResolutionPassesFocusAndClearsPasses() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.turnState = .showdownOpen(Self.openShowdown(attacker: playerA, defender: playerB, battlefield: battlefieldID))

        let spell = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell"), owner: playerA,
            name: "Showdown Spell", type: .spell
        )
        ChainResolver.push(.spell(spell, targets: [], instructions: []), proposedBy: playerA, to: &state)

        ChainResolver.pass(by: playerA, in: &state)
        let outcome = ChainResolver.pass(by: playerB, in: &state)

        #expect(outcome.resolvedItem != nil)
        guard case .showdownOpen(let showdown) = state.turnState else {
            Issue.record("Expected to be back at Showdown Open, got \(state.turnState)")
            return
        }
        #expect(showdown.focusPlayer == playerB)      // 552
        #expect(showdown.passedPlayers.isEmpty)        // fresh sequence
    }

    /// 550.1: a Combat Showdown's Relevant Players are just the attacker
    /// and defender, even at a larger table — so Focus skips the seats in
    /// between rather than stalling on a player who can't act.
    @Test("Focus skips players who are not Relevant to this Showdown")
    func focusSkipsNonRelevantPlayers() {
        let playerA = TestFixtures.makePlayer()
        let playerB = TestFixtures.makePlayer()
        let playerC = TestFixtures.makePlayer()
        let battlefield = TestFixtures.makeBattlefield(owner: playerA)

        var state = GameState(
            turnOrder: [playerA, playerB, playerC],
            battlefields: [battlefield.id: battlefield],
            zones: [
                playerA: TestFixtures.makeZones(owner: playerA),
                playerB: TestFixtures.makeZones(owner: playerB),
                playerC: TestFixtures.makeZones(owner: playerC)
            ]
        )
        state.phase = .action
        // A and C are fighting; B is sitting between them in turn order and
        // is not Relevant.
        state.turnState = .showdownOpen(Self.openShowdown(attacker: playerA, defender: playerC, battlefield: battlefield.id))

        ChainResolver.pass(by: playerA, in: &state)

        guard case .showdownOpen(let showdown) = state.turnState else {
            Issue.record("Expected the Showdown to still be open, got \(state.turnState)")
            return
        }
        #expect(showdown.focusPlayer == playerC)
    }

    /// 140.1.c: "This action cannot be performed during a Showdown." The
    /// Showdown is a real pause — you can't keep feeding units into it.
    @Test("A Standard Move is illegal while a Showdown is in progress")
    func standardMoveIllegalDuringShowdown() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit
        state.turnState = .showdownOpen(Self.openShowdown(attacker: playerA, defender: playerB, battlefield: battlefieldID))

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        )

        #expect(!result.isSuccess)
    }
}
