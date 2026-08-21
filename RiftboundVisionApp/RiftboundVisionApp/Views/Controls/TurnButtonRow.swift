import SwiftUI
import RiftboundVision

/// Next · Back · End Turn.
///
/// **None of these is disabled by Auto-advance.** It can only move a phase
/// it can confirm, and a hand fanned over the mat is countable only
/// sometimes — greying the controls out turns a stall into a dead end, with
/// the toggle the only way out. The assist must never be the thing standing
/// between a player and their turn.
struct TurnButtonRow: View {
    @Binding var gameState: ManualGameState
    /// Set when the player declares they're done playing cards, which is
    /// what arms End Turn. 516.2 gives the Action Phase no completion
    /// condition, so nothing but the player can say this.
    @Binding var hasDeclaredActions: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(nextTitle) {
                if gameState.phase == .action {
                    hasDeclaredActions = true
                } else {
                    gameState.advance()
                }
            }
            .buttonStyle(RiftPrimaryButtonStyle())
            .disabled(gameState.phase == .action && hasDeclaredActions)

            Button("Back") { gameState.back() }
                .buttonStyle(RiftPrimaryButtonStyle())
                .disabled(!gameState.canGoBack)

            Button("End Turn") {
                gameState.endTurn()
                hasDeclaredActions = false
            }
            .buttonStyle(RiftSecondaryButtonStyle())
            .disabled(gameState.phase != .action || !hasDeclaredActions)
        }
    }

    /// In the Action Phase "Next" means "I'm done playing" — there is no
    /// next phase to step to (516.6), only the declaration that arms End
    /// Turn.
    private var nextTitle: String {
        gameState.phase == .action ? "Done" : "Next"
    }
}
