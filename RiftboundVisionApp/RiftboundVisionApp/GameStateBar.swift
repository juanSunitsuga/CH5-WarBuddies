import SwiftUI
import RiftboundVision

/// Manual round/turn/phase control — the vision pipeline can see a card
/// rotate or move, but it can't see a player declare "I'm ending my turn,"
/// so this is set by hand rather than detected. Lets the user jump
/// straight to any round/phase, not just step forward one at a time.
struct GameStateBar: View {
    @Binding var gameState: ManualGameState

    var body: some View {
        HStack(spacing: 16) {
            Stepper(value: $gameState.round, in: 1...999) {
                Text("Round \(gameState.round)")
                    .font(.headline)
                    .monospacedDigit()
            }
            .fixedSize()

            // No Opponent seat to pick — this app tracks one physical
            // mat/camera only, so "whose turn" isn't a real choice here.

            Picker("Phase", selection: $gameState.phase) {
                ForEach(GamePhase.allCases, id: \.self) { phase in
                    Text(phase.displayName).tag(phase)
                }
            }
            .frame(width: 160)

            Spacer()

            Button {
                gameState.advance()
            } label: {
                Label("Advance", systemImage: "forward.fill")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.85))
        .foregroundStyle(.white)
    }
}
