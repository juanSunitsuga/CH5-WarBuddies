import SwiftUI
import RiftboundVision

/// Back · Next, with Next itself becoming End Turn once the phase is
/// `.action`.
///
/// This used to be three buttons: Next/Done, Back, and a separately-armed
/// End Turn that only lit up once the player had pressed Done. That middle
/// step didn't correspond to anything in the rules — 516.6 makes *ending
/// the turn* the player's declaration, so pressing End Turn already **is**
/// "I'm done playing"; asking for a Done press first just to arm it was a
/// confirmation this app invented, not one the rules asked for. Next simply
/// relabels itself once there's nowhere left to advance *to*.
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
        case .action: return "Marks your turn's actions finished, without passing play yet"
        case .done: return "Ends your turn and passes play to your opponent"
        default: return "Moves on to the next phase of your turn"
        }
    }

    /// Three labels, because the last two steps are different declarations.
    ///
    /// Action offers **Done** — "I've finished playing" — and only the
    /// `.done` state that follows offers **End Turn**, which is the 516.6
    /// hand-over. Splitting them means the button that gives your turn
    /// away is never the one sitting under your cursor while you're still
    /// playing cards.
    private var nextTitle: String {
        switch gameState.phase {
        case .action: return "Done"
        case .done: return "End Turn"
        default: return "Next"
        }
    }
}
