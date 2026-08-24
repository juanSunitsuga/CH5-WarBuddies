import SwiftUI
import RiftboundVision

/// The turn's state and the controls that move it.
struct PhaseIndicatorSection: View {
    @Binding var gameState: ManualGameState
    @Binding var isAutoAdvancing: Bool
    @Binding var isExpanded: Bool
    /// Whether `CameraPipelineController`'s pipeline is running. Before
    /// Start Game is pressed there's no turn to track, so every control
    /// that moves the turn along — Auto-advance and the button row — stays
    /// disabled.
    let isGameRunning: Bool

    /// Split into two nested stacks rather than one flat list of children
    /// purely so the guided tour can point at each half separately — it
    /// has a beat for reading the turn's state and a later one for the
    /// controls that move it. The outer stack keeps the same spacing the
    /// flat version had, so the split is invisible on screen.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                RiftSectionHeader(title: "Phase Indicator", isExpanded: $isExpanded)

                if isExpanded {
                    Text("Track your turn steps here.")
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))

                    Text("Start of Turn Phases")
                        .font(RiftboundFont.subheading)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))

                    PhasePipRow(current: gameState.phase)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(RiftboundPhaseCopy.title(for: gameState.phase))
                            .font(RiftboundFont.heading)
                            .foregroundStyle(RiftboundPalette.regularText)
                        Text(RiftboundPhaseCopy.blurb(for: gameState.phase))
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            // Reserves room for the longest blurb (Action's, at
                            // two lines) so Back/Next/End Turn sit at the same
                            // height regardless of which phase is showing.
                            .frame(minHeight: RiftboundLayout.phaseBlurbMinHeight, alignment: .topLeading)
                    }
                }
            }
            .tourRegion(.phaseIndicator)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    autoAdvanceRow
                    TurnButtonRow(gameState: $gameState, isGameRunning: isGameRunning)
                }
                .tourRegion(.turnControls)
            }
        }
    }

    private var autoAdvanceRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isAutoAdvancing) {
                Text("Auto-advance")
                    .font(RiftboundFont.subheading)
                    .foregroundStyle(
                        isAutoAdvancing
                            ? RiftboundPalette.highlightOverlay
                            : RiftboundPalette.regularText.opacity(0.7)
                    )
            }
            .toggleStyle(RiftSwitchToggleStyle())
            .fixedSize()
            .disabled(!isGameRunning)
            // `RiftSwitchToggleStyle` is hand-drawn, not a system control,
            // so `.disabled` alone stops it responding but doesn't dim it —
            // nothing inside reads `@Environment(\.isEnabled)`. Apply the
            // board's own disabled-opacity rule explicitly.
            .riftComponentDisabled(!isGameRunning)

            // Says what it will and won't do, where it's switched on.
            // Auto-advance moves the four fixed phases and stops at the
            // Action Phase: 516.6 makes ending a turn the player's
            // declaration, and nothing the camera sees substitutes for it.
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                .help("Moves through Awaken, Beginning, Channel and Draw when the table shows each step done. Your turn, and ending it, stay yours.")
                .accessibilityLabel("Auto-advance moves the start-of-turn phases only.")
        }
    }
}
