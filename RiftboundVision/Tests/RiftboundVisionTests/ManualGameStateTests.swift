import Testing
@testable import RiftboundVision

struct ManualGameStateTests {

    @Test("Advancing steps through the fixed phase order without changing turn player")
    func advanceStepsThroughPhases() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .awaken)
        state.advance()
        #expect(state.phase == .beginning)
        #expect(state.turnPlayer == .player1)
        #expect(state.round == 1)
    }

    @Test("Rule 506: Cleanup completing hands the turn to the other player, same round")
    func cleanupHandsOffTurnWithoutIncrementingRoundYet() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .cleanup)
        state.advance()
        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player2)
        #expect(state.round == 1)
    }

    @Test("Rule 115.1.b.1: play cycling back to the First Player increments round")
    func cyclingBackToFirstPlayerIncrementsRound() {
        var state = ManualGameState(round: 1, turnPlayer: .player2, phase: .cleanup)
        state.advance()
        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player1)
        #expect(state.round == 2)
    }
}
