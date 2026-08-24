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

    @State private var isShowingAutoAdvanceInfo = false

    /// One string for the popover, the hover tooltip and the
    /// accessibility label. They carried two different wordings before,
    /// which meant VoiceOver described the control differently from what
    /// everyone else could read.
    private static let autoAdvanceInfo =
        "Let BonBon scan the table and advance the steps automatically for you."

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
            //
            // A real `Button` with a `.popover`, not TipKit: a `Tip` is
            // built to appear once on its own schedule and then stay
            // dismissed for good, which is the opposite of what an info
            // button owes you — it has to answer every time it's pressed.
            // `.help` stays on top of it so hovering still gives the same
            // sentence without a click.
            Button { isShowingAutoAdvanceInfo.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Self.autoAdvanceInfo)
            .accessibilityLabel(Self.autoAdvanceInfo)
            .popover(isPresented: $isShowingAutoAdvanceInfo, arrowEdge: .bottom) {
                Text(Self.autoAdvanceInfo)
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 220, alignment: .leading)
                    .padding(14)
                    // The popover's own chrome is the system's, which is
                    // light — without this the one panel in the app that
                    // isn't the board's navy.
                    .presentationBackground(RiftboundPalette.mainBackground)
            }
        }
    }
}
