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

    /// `.done` sits between Action and the hand-off: the player declares
    /// they have finished playing, and only then is the turn given up.
    /// Pins the step that used to be absent — advancing from Action once
    /// handed the turn straight over.
    @Test("Advancing from Action reaches Done, not the next player")
    func actionAdvancesToDone() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .action)
        state.advance()
        #expect(state.phase == .done)
        #expect(state.turnPlayer == .player1, "Declaring you're finished must not hand the turn over on its own.")
        #expect(state.round == 1)
    }

    @Test("Rule 506: advancing from Done hands the turn to the other player, same round")
    func doneHandsOffTurnWithoutIncrementingRoundYet() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .done)
        state.advance()
        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player2)
        #expect(state.round == 1)
    }

    @Test("Rule 115.1.b.1: play cycling back to the First Player increments round")
    func cyclingBackToFirstPlayerIncrementsRound() {
        var state = ManualGameState(round: 1, turnPlayer: .player2, phase: .done)
        state.advance()
        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player1)
        #expect(state.round == 2)
    }

    /// With `.done` last, `advance()` and `endTurn()` do the same thing
    /// from there — which is why that phase offers End Turn rather than a
    /// third label.
    @Test("From Done, advancing and ending the turn agree")
    func advanceAndEndTurnAgreeFromDone() {
        var advanced = ManualGameState(round: 1, turnPlayer: .player1, phase: .done)
        var ended = ManualGameState(round: 1, turnPlayer: .player1, phase: .done)
        advanced.advance()
        ended.endTurn()
        #expect(advanced == ended)
    }

    /// They must *not* agree from Action — that's the whole point of the
    /// step. End Turn is still the 516.6 fast path from anywhere.
    @Test("From Action, advancing and ending the turn differ")
    func advanceAndEndTurnDifferFromAction() {
        var advanced = ManualGameState(round: 1, turnPlayer: .player1, phase: .action)
        var ended = ManualGameState(round: 1, turnPlayer: .player1, phase: .action)
        advanced.advance()
        ended.endTurn()
        #expect(advanced != ended)
        #expect(ended.phase == .awaken)
        #expect(ended.turnPlayer == .player2)
    }

    /// Rule 516.2: the Action Phase is the only phase whose contents the
    /// player chooses, so it's the only one where the app has a move to
    /// judge. During the fixed prefix it should be telling them what to do
    /// instead — see `TurnControlBar`.
    @Test("Only the Action Phase, and its Done sub-state, validate player moves")
    func onlyActionPhaseValidatesMoves() {
        #expect(GamePhase.action.validatesPlayerMoves)
        // The turn has not ended in `.done`, so by 516 the player is
        // still choosing what happens and the app still has a move to
        // judge.
        #expect(GamePhase.done.validatesPlayerMoves)
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

/// `back()` is an undo of the app's own bookkeeping, not a game action —
/// nothing in 515 moves a turn backwards. It exists because the phase is
/// asserted by a human and sometimes guessed by Auto-advance, and both can
/// be wrong.
struct ManualGameStateBackTests {

    @Test("Back steps to the previous phase")
    func backStepsBackwards() {
        var state = ManualGameState(round: 1, turnPlayer: .player1, phase: .channel)
        state.back()
        #expect(state.phase == .beginning)
    }

    /// Wrapping would hand the turn to a player who already finished it —
    /// much worse to land in by accident than simply not moving.
    @Test("Back stops at Awaken rather than wrapping to the previous player")
    func backStopsAtAwaken() {
        var state = ManualGameState(round: 2, turnPlayer: .player2, phase: .awaken)
        state.back()

        #expect(state.phase == .awaken)
        #expect(state.turnPlayer == .player2)
        #expect(state.round == 2)
    }

    @Test("canGoBack is false only at Awaken")
    func canGoBackReportsTheEdge() {
        #expect(!ManualGameState(phase: .awaken).canGoBack)
        for phase in [GamePhase.beginning, .channel, .draw, .action] {
            #expect(ManualGameState(phase: phase).canGoBack, "\(phase.displayName) should be able to step back.")
        }
    }

    @Test("Back undoes advance for every phase")
    func backUndoesAdvance() {
        for phase in [GamePhase.awaken, .beginning, .channel, .draw] {
            var state = ManualGameState(phase: phase)
            state.advance()
            state.back()
            #expect(state.phase == phase)
        }
    }
}
