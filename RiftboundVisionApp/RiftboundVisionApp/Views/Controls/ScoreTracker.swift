import SwiftUI

/// Rule 190/191: the game is won at 8 points. Scored points are the one
/// piece of game state the camera genuinely cannot see — points are
/// tracked on a physical score dial or by agreement, not by cards moving —
/// so like `ManualGameState` this is asserted by the person at the table
/// rather than inferred.
///
/// Visually this is where the board's "Iconics" 80pt size is used: the two
/// numerals are the largest thing in the window on purpose, because they
/// are read across a table rather than from a keyboard's distance.
struct ScoreTracker: View {
    @Binding var playerScore: Int
    @Binding var opponentScore: Int
    /// Whether `CameraPipelineController`'s pipeline is running. Points are
    /// asserted by the person at the table (see the doc comment above), but
    /// only during a game — there is nothing to score before Start Game,
    /// so the whole tracker dims and its steppers stop responding rather
    /// than offering a control that quietly edits the *next* game's score.
    var isGameRunning: Bool = true

    /// Rule 191.1: first to 8 points wins.
    static let winningScore = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("First to \(Self.winningScore) points win.")
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText)

                Spacer()

                Button {
                    playerScore = 0
                    opponentScore = 0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RiftboundPalette.regularText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isGameRunning)
                .riftComponentDisabled(!isGameRunning)
                .help("Reset score to 0 – 0")
                .accessibilityLabel("Reset score")
            }

            HStack(spacing: 14) {
                counter(title: "Player", score: $playerScore)
                counter(title: "Opponent", score: $opponentScore)
            }
        }
    }

    private func counter(title: String, score: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RiftboundPalette.primaryButton)

            // 80pt with a tight, fixed frame — at this size the default
            // line box adds a lot of leading, which pushed the numeral
            // off-centre inside the gold panel.
            Text("\(score.wrappedValue)")
                .font(RiftboundFont.iconic)
                .monospacedDigit()
                .foregroundStyle(RiftboundPalette.regularText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .background(RiftboundPalette.highlightOverlay)

            HStack(spacing: 0) {
                stepButton(systemName: "minus", label: "Subtract a point from \(title)") {
                    score.wrappedValue = max(0, score.wrappedValue - 1)
                }
                Rectangle()
                    .fill(RiftboundPalette.regularText.opacity(0.35))
                    .frame(width: 1, height: 18)
                stepButton(systemName: "plus", label: "Add a point to \(title)") {
                    score.wrappedValue = min(Self.winningScore, score.wrappedValue + 1)
                }
            }
            .background(RiftboundPalette.primaryButton)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .riftComponentDisabled(!isGameRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) score")
        .accessibilityValue("\(score.wrappedValue) of \(Self.winningScore)")
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(RiftboundPalette.regularText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isGameRunning)
        .accessibilityLabel(label)
    }
}

#Preview {
    ScoreTracker(playerScore: .constant(3), opponentScore: .constant(0))
        .padding()
        .frame(width: 340)
        .background(RiftboundPalette.secondaryBackground)
}
