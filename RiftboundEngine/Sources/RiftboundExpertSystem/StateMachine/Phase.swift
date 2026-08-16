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
/// player who goes **last** in Turn Order Channels one extra Rune on their
/// own first turn (644.7/645.7 for 1v1, 646.7/647.7/648.7 for the larger
/// modes — all four word it as the player going last/second), to offset
/// never getting the first player's opening tempo.
///
/// Pure functions rather than anything read off live state, so the same
/// rule answers both questions that need it: what to Channel *now*
/// (`runesToChannel`, used by the Channel Phase) and what should have been
/// Channeled *in total by now* (`expectedRunesChanneled`, used by the
/// vision layer's pace/anomaly check against the physical Rune Area).
public enum RuneChannelPace {
    /// Rule 515.3.b: 2 Runes, plus 1 if this is the last player's own first
    /// turn.
    ///
    /// - Parameters:
    ///   - player: who is Channeling.
    ///   - turnOrder: rule 115.1's Turn Order — its *last* element is the
    ///     player who gets the extra Rune.
    ///   - completedTurns: how many of `player`'s own turns have already
    ///     finished their Channel Step. `0` means the one about to happen
    ///     is their first.
    public static func runesToChannel(
        for player: PlayerID,
        turnOrder: [PlayerID],
        completedTurns: Int
    ) -> Int {
        let goesLast = turnOrder.count > 1 && turnOrder.last == player
        return goesLast && completedTurns == 0 ? 3 : 2
    }

    /// Cumulative total a player should have Channeled after
    /// `completedTurns` of their own turns — the sum of `runesToChannel`
    /// over those turns.
    ///
    /// This is *not* the number of Runes that should be visible in their
    /// Rune Area: Recycling returns a Rune to the Rune Deck (594.1.b), so
    /// the visible count is this minus `GameState.totalRunesRecycled`.
    public static func expectedRunesChanneled(
        for player: PlayerID,
        turnOrder: [PlayerID],
        completedTurns: Int
    ) -> Int {
        guard completedTurns > 0 else { return 0 }
        let goesLast = turnOrder.count > 1 && turnOrder.last == player
        let firstTurnBonus = goesLast ? 1 : 0
        return completedTurns * 2 + firstTurnBonus
    }
}
