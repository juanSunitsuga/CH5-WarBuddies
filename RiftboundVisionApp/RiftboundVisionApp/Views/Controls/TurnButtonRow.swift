import SwiftUI
import RiftboundVision

/// Back · Next, where the primary button relabels itself as the turn
/// moves: **Next** through ABCD, **Done** in the Action Phase, and
/// **Start Turn** in the Done state that follows.
///
/// Back is live through the start-of-turn steps and the Action Phase, and
/// disabled once Done is pressed — see `ManualGameState.canGoBack`. That
/// press is the 516.6 declaration; the opponent takes their turn on the
/// strength of it, so there is nothing left to undo it back into.
///
/// **Neither button is disabled by Auto-advance.** It can only move a phase
/// it can confirm, and a hand fanned over the mat is countable only
/// sometimes — greying the controls out turns a stall into a dead end, with
/// the toggle the only way out. The assist must never be the thing standing
/// between a player and their turn.
struct TurnButtonRow: View {
    @Binding var gameState: ManualGameState
    /// Whether `CameraPipelineController`'s pipeline is running. Before
    /// Start Game is pressed there's no turn to move through, so the row
    /// stays disabled regardless of what phase state happens to say.
    let isGameRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Outlined, where Next/End Turn is solid gold. The two used to
            // be identical, which made every phase change a small reading
            // task: both buttons are live, both are gold, so the only
            // thing separating "the way forward" from "undo" was the
            // word. Weight now carries it — a filled button is the one
            // the turn expects you to press, and the outlined one is the
            // correction you take only if you meant to.
            Button("Back") { gameState.back() }
                .buttonStyle(RiftOutlineButtonStyle())
                .disabled(!isGameRunning || !gameState.canGoBack)
                // Spoken, the bare word "Back" doesn't say back to *what* —
                // and the two buttons here move through an order a sighted
                // player reads off the phase pips above, which VoiceOver
                // reaches only as a separate visit.
                .accessibilityHint(isGameRunning ? "Returns to the previous phase of your turn" : "Unavailable until the game is started")

            Button(nextTitle) {
                // Only `.done` ends the turn. Everything else — including
                // Action, which now steps to `.done` — advances a phase.
                if gameState.phase == .done {
                    gameState.endTurn()
                } else {
                    gameState.advance()
                }
            }
            .buttonStyle(RiftPrimaryButtonStyle())
            .disabled(!isGameRunning)
            .accessibilityHint(nextHint)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Turn controls, \(gameState.phase.displayName) phase")
    }

    /// What pressing the primary button will actually do, said out loud.
    private var nextHint: String {
        guard isGameRunning else { return "Unavailable until the game is started" }
        switch gameState.phase {
        case .action: return "Finishes your turn and passes play to your opponent. You can't go back after this"
        case .done: return "Starts your next turn — press it once your opponent has finished theirs"
        default: return "Moves on to the next phase of your turn"
        }
    }

    /// Three labels, because the last two steps are different moments.
    ///
    /// Action offers **Done** — the 516.6 declaration that finishes your
    /// turn. `.done` is then the wait while your opponent plays, and its
    /// button is **Start Turn**: pressed when *they* are finished, to
    /// begin your next one. So the button that gives your turn away is
    /// never the one under your cursor while you're still playing cards,
    /// and the button you press after the handover says what it starts
    /// rather than what it ended a while ago.
    private var nextTitle: String {
        switch gameState.phase {
        case .action: return "Done"
        case .done: return "Start Turn"
        default: return "Next"
        }
    }
}
