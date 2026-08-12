/// Rule 514–517: the fixed phase sequence of a turn. Names/ordering mirror
/// `RiftboundExpertSystem.Phase`/`StartOfTurnStep`/`EndOfTurnStep` on
/// purpose (without importing those types) — this is *not* driven by the
/// Expert System's own state machine, because nothing in this vision
/// pipeline can see whose turn it is or what phase they're in. A camera can
/// tell you a card rotated; it can't tell you a player declared they're
/// ending their turn. `ManualGameState` is the seam for the human at the
/// table to assert that fact directly, matching the Expert System's own
/// vocabulary so the two are never talking about different things.
public enum GamePhase: String, Sendable, Equatable, Codable, CaseIterable {
    case awaken      // 515.1: ready all Game Objects controlled by Turn Player
    case beginning   // 515.2: start-of-turn triggers, then Scoring/Holding
    case channel     // 515.3: channel 2 runes (+ any extra, e.g. first-turn rule)
    case draw        // 515.4: draw 1; Rune Pool empties at the end of this step
    case action      // 516: unstructured; Discretionary Actions until player ends turn
    case ending      // 517.1: end-of-turn triggers
    case expiration  // 517.2: clear damage, expire "this turn" effects, empty Rune Pool
    case cleanup     // 517.3: perform a Cleanup (rule 518-526)

    public var displayName: String {
        switch self {
        case .awaken: return "Awaken"
        case .beginning: return "Beginning"
        case .channel: return "Channel"
        case .draw: return "Draw"
        case .action: return "Action"
        case .ending: return "Ending"
        case .expiration: return "Expiration"
        case .cleanup: return "Cleanup"
        }
    }
}

/// The physical-table state this app has no way to infer from vision
/// alone: whose turn it is, which phase, and which round. The user sets
/// this by hand (see `RiftboundVisionApp`'s game-state bar) rather than it
/// being detected — same division of responsibility as
/// `PlaymatOverlayView`'s calibration, which the user drags into place
/// rather than the app guessing at.
///
/// Rule 115.1: Turn Order is a repeating sequence with no "round" as a
/// defined rules term — `round` here is just the practical count of how
/// many times Turn Order has cycled back to the First Player (115.1.b.1),
/// kept for the user's own bookkeeping and this app's UI. It is never read
/// by `RiftboundExpertSystem`.
public struct ManualGameState: Sendable, Equatable {
    public var round: Int
    public var turnPlayer: Player
    public var phase: GamePhase

    public init(round: Int = 1, turnPlayer: Player = .player1, phase: GamePhase = .awaken) {
        self.round = round
        self.turnPlayer = turnPlayer
        self.phase = phase
    }

    private static let phaseOrder: [GamePhase] = [.awaken, .beginning, .channel, .draw, .action, .ending, .expiration, .cleanup]

    /// Rule 506: the Turn Player changes once the current Turn Player
    /// reaches the end of all Phases of their Turn. Steps to the next
    /// phase in sequence; past `.cleanup` it wraps to the other seat's
    /// `.awaken` and, once play has cycled back to `.player1`, increments
    /// `round`.
    public mutating func advance() {
        guard let index = Self.phaseOrder.firstIndex(of: phase) else { return }
        if index + 1 < Self.phaseOrder.count {
            phase = Self.phaseOrder[index + 1]
            return
        }
        phase = .awaken
        turnPlayer = (turnPlayer == .player1) ? .player2 : .player1
        if turnPlayer == .player1 {
            round += 1
        }
    }
}
