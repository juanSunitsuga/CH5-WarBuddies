import SwiftUI

/// Rule 190/191: the game is won at 8 points. Scored points are the one
/// piece of game state the camera genuinely cannot see — points are
/// tracked on a physical score dial or by agreement, not by cards moving —
/// so like `ManualGameState` this is asserted by the person at the table
/// rather than inferred.
struct ScoreTracker: View {
    @Binding var playerScore: Int
    @Binding var opponentScore: Int

    /// Rule 191.1: first to 8 points wins.
    static let winningScore = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First to \(Self.winningScore) points win.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 12) {
                counter(title: "Player", score: $playerScore)
                counter(title: "Opponent", score: $opponentScore)
            }
        }
    }

    private func counter(title: String, score: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color(red: 0.55, green: 0.34, blue: 0.13))

            Text("\(score.wrappedValue)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.99, green: 0.96, blue: 0.87))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(red: 0.82, green: 0.51, blue: 0.24))

            HStack(spacing: 0) {
                stepButton(systemName: "minus") {
                    score.wrappedValue = max(0, score.wrappedValue - 1)
                }
                Divider().frame(height: 18).overlay(.white.opacity(0.35))
                stepButton(systemName: "plus") {
                    score.wrappedValue = min(Self.winningScore, score.wrappedValue + 1)
                }
            }
            .background(Color(red: 0.55, green: 0.34, blue: 0.13))
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
