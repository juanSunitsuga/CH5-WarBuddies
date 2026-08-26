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
    case action      // 516: unstructured; Discretionary Actions until the player ends the turn
    /// Not a rules phase — an app-side sub-state of the Action Phase.
    ///
    /// 516.6 makes *ending the turn* the player's declaration, and by the
    /// rules pressing End Turn is already that declaration, which is why
    /// an earlier version of this app removed the separate Done step as a
    /// confirmation it had invented. It is back by design: at a physical
    /// table "I've finished playing" and "hand the turn over" are two
    /// moments, and collapsing them meant the only button that ended a
    /// turn was one click away at all times during the phase where the
    /// player is handling the most cards.
    ///
    /// The turn is still in 516 while this is showing. Nothing about the
    /// rules state changes when Done is pressed — only what the panel
    /// says and which button is offered.
    case done

    // Rule 517's Ending, Expiration and Cleanup steps are deliberately
    // absent. They are real phases, but they contain nothing a player at
    // the table *does* — no triggers to declare, no cards to touch — so
    // presenting them as steps to click through asked the user to
    // acknowledge three screens of bookkeeping every turn. Ending the
    // Action Phase runs them and goes straight to the next Awaken, which
    // is what a turn looks like from a chair. `RiftboundExpertSystem`
    // still models all three properly in `TurnSequencer.endTurn`; this
    // enum is the *player-facing* sequence, not the rules one.

    public var displayName: String {
        switch self {
        case .awaken: return "Awaken"
        case .beginning: return "Beginning"
        case .channel: return "Channel"
        case .draw: return "Draw"
        case .action: return "Action"
        case .done: return "Done"
        }
    }

    /// What the player should physically do right now.
    ///
    /// Phrased as an instruction rather than a rules summary, because
    /// during the four fixed phases this is the *only* thing the bar shows
    /// — the app deliberately withholds verdicts about detected card
    /// movement until the Action Phase (see `TurnControlBar`). Before then
    /// the player is following a script, and commentary on each card they
    /// touch while following it is noise.
    public var instruction: String {
        switch self {
        case .awaken:
            return "Turn every exhausted card you control upright — units, gear and runes (Rule 515.1)."
        case .beginning:
            return "Score 1 point for each battlefield you still control, then hit Next (Rule 515.2/630.2)."
        case .channel:
            return "Put 2 runes from your rune deck into your rune area, face up and ready (Rule 515.3)."
        case .draw:
            return "Draw 1 card. Any unspent energy and power is lost at the end of this step (Rule 515.4)."
        case .action:
            return "Play or move any card. I'll let you know if it's wrong (Rule 516)."
        case .done:
            return "Your turn is over — your opponent plays now. Start Turn once they've finished theirs (Rule 516.6)."
        }
    }

    /// Whether the app should judge what it sees during this phase.
    ///
    /// Only the Action Phase, because it's the only phase whose contents
    /// the player chooses (516.2). Everything the camera picks up during
    /// Awaken, Beginning, Channel and Draw is the player carrying out a
    /// fixed script — readying cards, dealing runes — and narrating that
    /// back to them ("Nothing to do for Chaos Rune") is noise dressed as
    /// feedback. Worse, it competes for the same line of screen with the
    /// instruction telling them what to do.
    /// `.done` counts too: the turn has not ended, so by the rules the
    /// player is still in 516 and anything the camera sees is still a
    /// move they chose. It is also the moment they're most likely to have
    /// mis-clicked — going quiet exactly when someone says "I'm finished"
    /// would hide the very mistake worth catching.
    /// Whether this is one of 515's four lettered start-of-turn steps —
    /// the ones the A/B/C/D pips actually stand for.
    ///
    /// Asked as a property rather than spelled out as `!= .action &&
    /// != .done` at the call site, so adding another post-Action state
    /// can't leave the pip row lit through it by omission.
    public var isStartOfTurn: Bool {
        switch self {
        case .awaken, .beginning, .channel, .draw: return true
        case .action, .done: return false
        }
    }

    public var validatesPlayerMoves: Bool {
        self == .action || self == .done
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

    private static let phaseOrder: [GamePhase] = [.awaken, .beginning, .channel, .draw, .action, .done]

    /// Rule 506: the Turn Player changes once the current Turn Player
    /// reaches the end of all Phases of their Turn. Steps to the next
    /// phase in sequence; past `.action` it wraps to the other seat's
    /// `.awaken` and, once play has cycled back to `.player1`, increments
    /// `round`.
    ///
    /// **Nothing follows the Action Phase in the rules.** 516.6 ends it
    /// when the player says so, and 517's steps are automatic bookkeeping
    /// with nothing to do in them. `.done` is the one app-side step after
    /// it — a declaration that the player has stopped playing, not a
    /// phase — and advancing past *that* hands the turn over, the same
    /// thing `endTurn()` does.
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

    /// Steps back one phase, for correcting a mis-advance.
    ///
    /// Nothing in the rules moves a turn backwards — 515's steps are
    /// one-way — so this is explicitly an *undo of the app's own
    /// bookkeeping*, not a game action. It exists because the phase is
    /// asserted by a human (and now sometimes guessed by Auto-advance), and
    /// both can be wrong; without it the only correction was ending the
    /// turn and losing the rest of it.
    ///
    /// Stops at `.awaken` rather than wrapping to the previous player.
    /// Wrapping would hand the turn back to someone who has already
    /// finished, which is a far worse state to land in by mistake than
    /// simply not moving.
    public mutating func back() {
        guard canGoBack, let index = Self.phaseOrder.firstIndex(of: phase) else { return }
        phase = Self.phaseOrder[index - 1]
    }

    /// Whether `back()` would do anything — for disabling the control
    /// rather than offering a button that no-ops.
    ///
    /// False at `.awaken`, where there is no earlier phase, and false at
    /// `.done`, where there deliberately isn't a way back. Pressing Done
    /// is the player declaring their turn finished; the opponent takes
    /// over on the strength of that declaration, so un-declaring it
    /// afterwards would mean taking back a turn someone else has already
    /// started playing against.
    public var canGoBack: Bool {
        guard phase != .done else { return false }
        return (Self.phaseOrder.firstIndex(of: phase) ?? 0) > 0
    }

    /// Rule 506: jumps straight to the next Turn Player's Awaken phase
    /// regardless of which phase is currently active — the "I'm done, end
    /// my turn now" fast path, as opposed to `advance()`'s one-step-at-a-
    /// time progression through 515–517.
    public mutating func endTurn() {
        phase = .awaken
        turnPlayer = (turnPlayer == .player1) ? .player2 : .player1
        if turnPlayer == .player1 {
            round += 1
        }
    }
}
