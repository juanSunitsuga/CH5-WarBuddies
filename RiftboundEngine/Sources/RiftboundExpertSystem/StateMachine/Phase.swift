/// Rule 514–517: the rigid phase sequence of a turn. Actions within a phase
/// can happen in any order (503), but phases themselves are strictly
/// ordered and each must fully complete before the next begins.
public enum Phase: Sendable, Equatable {
    case startOfTurn(StartOfTurnStep)
    case action                  // 516: unstructured; Discretionary Actions until player ends turn
    case endOfTurn(EndOfTurnStep)
}

/// Rule 515: the four fixed sub-steps of Start of Turn, in order.
public enum StartOfTurnStep: Sendable, Equatable {
    case awaken      // 515.1: ready all Game Objects controlled by Turn Player
    case beginning   // 515.2: start-of-turn triggers, then Scoring/Holding
    case channel     // 515.3: channel 2 runes (+ any extra, e.g. first-turn rule)
    case draw        // 515.4: draw 1; Rune Pool empties at the end of this step (515.4.d)
}

/// Rule 517: the three fixed sub-steps of End of Turn, in order.
public enum EndOfTurnStep: Sendable, Equatable {
    case ending        // 517.1: end-of-turn triggers
    case expiration     // 517.2: clear damage, expire "this turn" effects, empty Rune Pool
    case cleanup         // 517.3: perform a Cleanup (rule 518-526)
    // 517.4: if further damage/eeffects were generated, loop back to
    // .expiration — model this as a controller-level loop, not a case.
}

/// Rule 515.3's "+ any extra, e.g. first-turn rule" made concrete: the
/// player who does NOT go first Channels 3 Runes on their own first turn
/// instead of 2, to offset never getting the first player's opening
/// tempo. A pure function rather than something read off live state,
/// since turn-count tracking itself is still a manual, human-driven input
/// (see `RiftboundVision.ManualGameState`) — this only answers "given that
/// many completed turns for this player, what's the expected cumulative
/// total," ready for whichever pace/anomaly check ends up calling it.
public enum RuneChannelPace {
    /// - Parameters:
    ///   - player: whose cumulative total to compute.
    ///   - turnOrder: rule 115.1's Turn Order — `turnOrder[1]`, if present,
    ///     is the player who goes second.
    ///   - completedTurns: how many of `player`'s own turns have finished
    ///     their Channel step (not a global/shared turn counter).
    public static func expectedRunesChanneled(
        for player: PlayerID,
        turnOrder: [PlayerID],
        completedTurns: Int
    ) -> Int {
        guard completedTurns > 0 else { return 0 }
        let goesSecond = turnOrder.count > 1 && turnOrder[1] == player
        let firstTurnBonus = goesSecond ? 1 : 0
        return completedTurns * 2 + firstTurnBonus
    }
}
