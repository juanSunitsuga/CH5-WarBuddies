import SwiftUI
import RiftboundVision

/// The right-hand column: everything the player operates, and the score.
///
/// The controls used to live in a bar under the camera, spread across three
/// phase cards, a status strip and a button row. Gathering them here leaves
/// the left column as just the board — cards, camera, and what BonBon is
/// saying — which is the split the reference draws.
///
/// It also fixed an ordering problem the bottom bar had: the buttons sat to
/// the *right* of the phase cards, so the control and the thing it changed
/// were at opposite ends of a wide window. Stacked, the pips are directly
/// above the button that moves them.
///
/// This type owns arrangement and the state the sections share; the
/// sections themselves are `PhaseIndicatorSection` and `ScoreSection`.
struct TurnControlColumn: View {
    @Binding var gameState: ManualGameState
    @Binding var isAutoAdvancing: Bool
    @Binding var playerScore: Int
    @Binding var opponentScore: Int

    @State private var hasDeclaredActions = false
    @State private var isPhaseSectionExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PhaseIndicatorSection(
                    gameState: $gameState,
                    isAutoAdvancing: $isAutoAdvancing,
                    hasDeclaredActions: $hasDeclaredActions,
                    isExpanded: $isPhaseSectionExpanded
                )

                Divider().overlay(RiftboundPalette.elementStroke.opacity(0.35))

                ScoreSection(playerScore: $playerScore, opponentScore: $opponentScore)
            }
            .padding(RiftboundLayout.controlColumnInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(width: RiftboundLayout.controlColumnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RiftboundPalette.secondaryBackground)
        .onChange(of: gameState.turnPlayer) { _, _ in hasDeclaredActions = false }
        .onChange(of: gameState.phase) { _, newPhase in
            if newPhase != .action { hasDeclaredActions = false }
        }
    }
}
