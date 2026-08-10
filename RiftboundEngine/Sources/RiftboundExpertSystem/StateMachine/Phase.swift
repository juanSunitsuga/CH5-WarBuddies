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
