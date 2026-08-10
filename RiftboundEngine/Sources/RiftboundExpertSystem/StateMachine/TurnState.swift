/// Rule 507–510: at any moment the turn is in exactly one of these four
/// states. This single enum should be the *only* place that answers "what
/// can be played right now" — legality checks pattern-match on it rather
/// than checking scattered booleans.
///
///   - Neutral Open   (510.1): no Showdown, no Chain. Default state; only
///                     the Turn Player may play cards/activate abilities
///                     (516.2.b), except in Team modes (516.2.b.1, 648.8.a).
///   - Neutral Closed  (510.2): no Showdown, a Chain exists. Only Reaction-
///                     tagged cards/abilities may be played (509.1.a).
///   - Showdown Open   (510.3): a Showdown is in progress, no Chain. Only
///                     Action/Reaction-tagged cards/abilities may be played
///                     (508.1.a), by the player with Focus (553).
///   - Showdown Closed (510.4): a Showdown is in progress AND a Chain
///                     exists inside it. Only Reaction-tagged items
///                     (509.1.a still applies; it's the stricter gate).
public enum TurnState: Sendable {
    case neutralOpen
    case neutralClosed(Chain)
    case showdownOpen(Showdown)
    case showdownClosed(Showdown, Chain)

    /// Rule 512.1.a / 553: who currently has Priority, if anyone. Priority
    /// grants permission to take Discretionary Actions (512.1). No player
    /// has Priority outside these cases (512.1.b).
    public func playerWithPriority(turnPlayer: PlayerID) -> PlayerID? {
        switch self {
        case .neutralOpen:
            return turnPlayer                                // 512.2.a
        case .neutralClosed(let chain):
            return chain.activePlayer                         // 512.2.c
        case .showdownOpen(let showdown):
            return showdown.focusPlayer                        // 512.2.b, 513.2
        case .showdownClosed(_, let chain):
            return chain.activePlayer                          // 512.2.c takes precedence while Chain exists
        }
    }

    /// Whether the turn is in a Closed state (509.1) — gates Reaction-only
    /// legality.
    public var isClosed: Bool {
        switch self {
        case .neutralClosed, .showdownClosed: return true
        case .neutralOpen, .showdownOpen: return false
        }
    }

    /// Whether a Showdown is currently in progress (508) — gates
    /// Action/Reaction-only legality.
    public var isShowdown: Bool {
        switch self {
        case .showdownOpen, .showdownClosed: return true
        case .neutralOpen, .neutralClosed: return false
        }
    }
}
