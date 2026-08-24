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
    let isPipelineRunning: Bool
    let isCameraRunning: Bool
    let onTogglePipeline: () -> Void
    /// The engine's own numbers — see `EnergySection`.
    var engineEnergy: Int?
    var engineReadyRunes: Int?
    var engineTotalRunes: Int?

    @State private var isPhaseSectionExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PhaseIndicatorSection(
                        gameState: $gameState,
                        isAutoAdvancing: $isAutoAdvancing,
                        isExpanded: $isPhaseSectionExpanded,
                        isGameRunning: isPipelineRunning
                    )
                    // `.phaseIndicator` and `.turnControls` are declared
                    // inside `PhaseIndicatorSection`, which is the only
                    // place that can tell its two halves apart.

                    Divider().overlay(RiftboundPalette.elementStroke.opacity(0.35))

                    // Reads the engine's ledger rather than the mat, so a
                    // disagreement between the two is visible.
                    EnergySection(
                        energy: engineEnergy,
                        readyRunes: engineReadyRunes,
                        totalRunes: engineTotalRunes
                    )

                    Divider().overlay(RiftboundPalette.elementStroke.opacity(0.35))

                    ScoreSection(playerScore: $playerScore, opponentScore: $opponentScore, isGameRunning: isPipelineRunning)
                        .tourRegion(.score)
                }
                .padding(RiftboundLayout.controlColumnInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)

            // Pinned below the scroll area rather than inside it, so it
            // stays reachable at the foot of the column regardless of how
            // tall the phase/score content above it grows.
            GameToggleButton(
                isRunning: isPipelineRunning,
                isCameraRunning: isCameraRunning,
                onToggle: onTogglePipeline
            )
            .tourRegion(.startGame)
            .padding(RiftboundLayout.controlColumnInset)
        }
        .frame(width: RiftboundLayout.controlColumnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RiftboundPalette.secondaryBackground)
    }
}
