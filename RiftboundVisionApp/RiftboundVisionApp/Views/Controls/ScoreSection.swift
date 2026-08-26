import SwiftUI

/// Score, with the sentence that says what scoring *is* — a bare pair of
/// numbers doesn't tell a new player that battlefields are how you get them.
struct ScoreSection: View {
    @Binding var playerScore: Int
    @Binding var opponentScore: Int
    let isGameRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score")
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)

            Text("Conquer and hold battlefields to get \(ScoreTracker.winningScore) points and win.")
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.regularText)
                .fixedSize(horizontal: false, vertical: true)

            ScoreTracker(playerScore: $playerScore, opponentScore: $opponentScore, isGameRunning: isGameRunning)
                // Same seam as the Phase Indicator's: the sentence above
                // explains what scoring is, and the tracker is the thing
                // it explains. They read as one paragraph without it.
                .padding(.top, RiftboundLayout.paragraphBreak)
        }
    }
}
