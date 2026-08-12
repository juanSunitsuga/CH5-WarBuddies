import SwiftUI
import RiftboundVision

/// Bottom bar: the current phase's instruction text, an "Auto-detect"
/// toggle, and the Next/End Turn buttons that actually move
/// `ManualGameState` forward. Auto-detect follows the same pattern as the
/// pipeline settings popover's unwired-stage rows — it's a real switch the
/// UI honors (it disables the manual buttons), but nothing in
/// `CameraPipelineController.process(_:)` drives it yet; see
/// `isAutoDetectingPhase`'s doc comment.
struct TurnControlBar: View {
    @Binding var gameState: ManualGameState
    @Binding var isAutoDetecting: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next Step")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(gameState.phase.instruction)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: $isAutoDetecting) {
                Text("Auto-detect")
                    .font(.callout.bold())
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .fixedSize()

            Button("Next") {
                gameState.advance()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAutoDetecting)

            Button("End Turn") {
                gameState.endTurn()
            }
            .buttonStyle(.bordered)
            .disabled(isAutoDetecting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.11, green: 0.23, blue: 0.33))
    }
}
