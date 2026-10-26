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
    /// Needed whole, not as further bindings, because `DebuggerPanel`
    /// reports on the pipeline rather than on any one value of it — the
    /// stage toggles, the telemetry and both logs are all its state.
    @ObservedObject var pipeline: CameraPipelineController
    @Binding var gameState: ManualGameState
    @Binding var isAutoAdvancing: Bool
    @Binding var playerScore: Int
    @Binding var opponentScore: Int
    let isPipelineRunning: Bool
    let isCameraRunning: Bool
    let onTogglePipeline: () -> Void

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

                    ScoreSection(playerScore: $playerScore, opponentScore: $opponentScore, isGameRunning: isPipelineRunning)
                        .tourRegion(.score)

                    Divider().overlay(RiftboundPalette.elementStroke.opacity(0.35))

                    // Below the score rather than above the phase pips: it
                    // is the one control here that is not part of playing a
                    // game, and a player who never needs it should not have
                    // to read past it to reach the ones they do.
                    Toggle(isOn: $pipeline.isDebuggerMode) {
                        Text("Debugger Mode")
                            .riftFont(.body)
                            .foregroundStyle(RiftboundPalette.regularText)
                    }
                    .toggleStyle(RiftSwitchToggleStyle())

                    if pipeline.isDebuggerMode {
                        DebuggerPanel(pipeline: pipeline)
                    }
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
