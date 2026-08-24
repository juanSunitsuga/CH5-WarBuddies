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

            Button(nextTitle) {
                if gameState.phase == .action {
                    gameState.endTurn()
                } else {
                    gameState.advance()
                }
            }
            .buttonStyle(RiftPrimaryButtonStyle())
            .disabled(!isGameRunning)
        }
    }

    /// In the Action Phase there is no next phase to step to (516.6) — only
    /// the declaration that ends the turn.
    private var nextTitle: String {
        gameState.phase == .action ? "End Turn" : "Next"
    }
}
