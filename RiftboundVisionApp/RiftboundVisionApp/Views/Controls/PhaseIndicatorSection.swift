import SwiftUI
import RiftboundVision

/// The turn's state and the controls that move it.
struct PhaseIndicatorSection: View {
    @Binding var gameState: ManualGameState
    @Binding var isAutoAdvancing: Bool
    @Binding var hasDeclaredActions: Bool
    @Binding var isExpanded: Bool

    var body: some View {
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
                }

                autoAdvanceRow
                TurnButtonRow(gameState: $gameState, hasDeclaredActions: $hasDeclaredActions)
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
