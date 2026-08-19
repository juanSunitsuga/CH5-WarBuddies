import SwiftUI
import RiftboundVision

/// Top header — the turn banner on the left, the "Terms and their
/// Meanings" legend beside it, and the round count trailing.
///
/// Still read-only display; advancement lives in `TurnControlBar` (see
/// that file for why phase/round can't be detected from the camera and has
/// to be asserted by the person at the table instead).
///
/// V3 changed what this bar *says*, not just how it looks. It used to
/// announce the phase ("Awaken Phase"), which duplicates the phase card
/// now sitting at the bottom of the window. What it announces instead is
/// whose turn it is, because that's the one thing the bottom row can't
/// tell you and the thing that decides whether you should be touching the
/// table at all.
///
/// `gameState.round` is deliberately not shown. It's still tracked on the
/// model and still incremented by `advance()`/`endTurn()` — it just has no
/// slot in this composition, and inventing one in the corner is how a
/// clean header turns into a dashboard.
struct GameStateBar: View {
    @Binding var gameState: ManualGameState

    /// Which seat the person using the app is sitting in. Everything in
    /// this app is written from one side of the table — `ScoreTracker`'s
    /// "Player"/"Opponent", `GameSessionBuilder`'s seeded hand — so the
    /// banner needs the same anchor to know whether "P2 Turn" means "your
    /// turn" or "watch and react".
    var localPlayer: Player = .player1

    private var isLocalTurn: Bool { gameState.turnPlayer == localPlayer }

    private var turnLabel: String {
        gameState.turnPlayer == .player1 ? "P1 Turn" : "P2 Turn"
    }

    /// The mockup's "Observe & React accordingly." is the *opponent's*-turn
    /// line. On your own turn that sentence would be wrong, so the other
    /// half of the pair is spelled out here rather than showing the same
    /// string for both seats.
    private var subtitle: String {
        isLocalTurn ? "Your move — take your turn." : "Observe & React accordingly."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Current Turn")
                    .font(RiftboundFont.subheading)
                    .foregroundStyle(RiftboundPalette.highlightOverlay)

                // "Iconics 2" on the board: 50pt. Tight line spacing keeps
                // the three lines reading as one block the way they do in
                // the mockup rather than as three stacked labels.
                Text(turnLabel)
                    .font(RiftboundFont.iconic2)
                    .foregroundStyle(RiftboundPalette.iconicText)
                    .lineSpacing(0)
                    .fixedSize()

                Text(subtitle)
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText)
            }

            TermsLegendView()

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RiftboundPalette.mainBackground)
    }
}

#Preview {
    GameStateBar(gameState: .constant(ManualGameState(round: 2, turnPlayer: .player2, phase: .action)))
}
