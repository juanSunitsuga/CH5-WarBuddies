import Testing
@testable import RiftboundVision

/// The player-facing turn sequence. Mirrors rules 514–517's *names* but not
/// its full step list: 517's Ending, Expiration and Cleanup contain nothing
/// a player at the table does, so the Action Phase is the last one shown.
struct ManualGameStateTests {

    @Test("Advancing steps through the fixed phase order without changing turn player")
    func advanceStepsThroughPhases() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .awaken)
        state.advance()
        #expect(state.phase == .beginning)
        #expect(state.turnPlayer == .player1)
        #expect(state.round == 1)
    }

    /// Rule 515: Awaken → Beginning → Channel → Draw → Action, and then it
    /// stops. Pinning the whole run because the shape of the turn is the
    /// thing being asserted, not any one transition.
    @Test("The fixed prefix runs Awaken through Draw and ends at Action")
    func fixedPrefixEndsAtAction() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .awaken)
        for expected in [GamePhase.beginning, .channel, .draw, .action] {
            state.advance()
            #expect(state.phase == expected)
        }
        #expect(state.turnPlayer == .player1)
    }

    /// Rule 516.6/517: nothing follows the Action Phase that the player
    /// takes part in, so advancing from it hands the turn over rather than
    /// walking three more steps of bookkeeping.
    @Test("Rule 506: advancing from Action hands the turn to the other player, same round")
    func actionHandsOffTurnWithoutIncrementingRoundYet() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .action)
        state.advance()
        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player2)
        #expect(state.round == 1)
    }

    @Test("Rule 115.1.b.1: play cycling back to the First Player increments round")
    func cyclingBackToFirstPlayerIncrementsRound() {
        var state = ManualGameState(round: 1, turnPlayer: .player2, phase: .action)
        state.advance()
        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player1)
        #expect(state.round == 2)
    }

    /// With Action last, `advance()` and `endTurn()` do the same thing from
    /// there — which is why the bar offers only one button in that phase.
    @Test("From Action, advancing and ending the turn agree")
    func advanceAndEndTurnAgreeFromAction() {
        var advanced = ManualGameState(round: 1, turnPlayer: .player1, phase: .action)
        var ended = ManualGameState(round: 1, turnPlayer: .player1, phase: .action)
        advanced.advance()
        ended.endTurn()
        #expect(advanced == ended)
    }

    /// Rule 516.2: the Action Phase is the only phase whose contents the
    /// player chooses, so it's the only one where the app has a move to
    /// judge. During the fixed prefix it should be telling them what to do
    /// instead — see `TurnControlBar`.
    @Test("Only the Action Phase validates player moves")
    func onlyActionPhaseValidatesMoves() {
        #expect(GamePhase.action.validatesPlayerMoves)
        for phase in [GamePhase.awaken, .beginning, .channel, .draw] {
            #expect(!phase.validatesPlayerMoves, "\(phase.displayName) should not judge moves.")
        }
    }

    /// Every phase shown to the player has to say what to physically do,
    /// since during the fixed prefix it's the only text on the bar.
    @Test("Every phase carries a player-facing instruction")
    func everyPhaseHasAnInstruction() {
        for phase in GamePhase.allCases {
            #expect(!phase.instruction.isEmpty)
            #expect(!phase.displayName.isEmpty)
        }
    }
}
