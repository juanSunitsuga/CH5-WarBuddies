import SwiftUI
import RiftboundVision

/// Top status header — "Current Turn" caption over the active phase, plus
/// the round count. Read-only display; actual advancement now lives in
/// `TurnControlBar`'s Next/End Turn buttons (see that file's doc comment
/// for why phase/round can't be detected from the camera and has to be
/// asserted by the person at the table instead).
struct GameStateBar: View {
    @Binding var gameState: ManualGameState

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Turn")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Text("\(gameState.phase.displayName) Phase")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Text("Round \(gameState.round)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(red: 0.11, green: 0.23, blue: 0.33))
    }
}
