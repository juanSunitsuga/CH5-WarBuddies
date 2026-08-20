import SwiftUI
import RiftboundVision

/// The right-hand column: everything the player operates, and the score.
///
/// The controls used to live in a bar under the camera, spread across three
/// phase cards, a status strip and a button row. Gathering them here leaves
/// the left column as just the board — cards, camera, and what BonBon is
/// saying — which is the split the V4 reference draws.
///
/// It also fixes an ordering problem the bottom bar had: the buttons sat to
/// the *right* of the phase cards, so the thing you press and the thing it
/// changes were at opposite ends of a wide window. Stacked, the pips are
/// directly above the button that moves them.
struct TurnControlColumn: View {
    @Binding var gameState: ManualGameState
    @Binding var isAutoAdvancing: Bool
    @Binding var playerScore: Int
    @Binding var opponentScore: Int

    /// Set when the player declares they're done playing cards — what arms
    /// End Turn. 516.2 gives the Action Phase no completion condition, so
    /// nothing but the player can say this.
    @State private var hasDeclaredActions = false
    @State private var isPhaseSectionExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                phaseSection
                Divider().overlay(RiftboundPalette.elementStroke.opacity(0.35))
                scoreSection
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(width: 362)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RiftboundPalette.secondaryBackground)
        .onChange(of: gameState.turnPlayer) { _, _ in hasDeclaredActions = false }
        .onChange(of: gameState.phase) { _, newPhase in
            if newPhase != .action { hasDeclaredActions = false }
        }
    }

    // MARK: - Phase indicator

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Phase Indicator", isExpanded: $isPhaseSectionExpanded)

            if isPhaseSectionExpanded {
                Text("Track your turn steps here.")
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))

                Text("Start of Turn Phases")
                    .font(RiftboundFont.subheading)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))

                pips

                VStack(alignment: .leading, spacing: 2) {
                    Text(RiftboundPhaseCopy.title(for: gameState.phase))
                        .font(RiftboundFont.heading)
                        .foregroundStyle(RiftboundPalette.regularText)
                    Text(gameState.phase.instruction)
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                autoAdvanceRow
                buttonRow
            }
        }
    }

    private var pips: some View {
        HStack(spacing: 10) {
            ForEach(RiftboundPhaseCopy.startOfTurnPhases, id: \.self) { phase in
                let isCurrent = gameState.phase == phase
                Text(RiftboundPhaseCopy.pipLetter(for: phase))
                    .font(RiftboundFont.heading)
                    .foregroundStyle(isCurrent ? RiftboundPalette.elementShadow : RiftboundPalette.regularText.opacity(0.7))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(isCurrent ? RiftboundPalette.highlightOverlay : Color.clear)
                    )
                    .overlay(
                        Circle().stroke(RiftboundPalette.elementStroke.opacity(isCurrent ? 0 : 0.5), lineWidth: 1)
                    )
                    .accessibilityLabel(phase.displayName)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
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

            // What it can and can't do, where it's switched on. Auto-advance
            // moves the four fixed phases and stops at the Action Phase —
            // 516.6 makes ending the turn the player's declaration, and
            // nothing the camera sees can substitute for it.
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                .help("Moves through Awaken, Beginning, Channel and Draw when the table shows each step done. Your turn and ending it stay yours.")
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            // Never disabled by Auto-advance. It can only move a phase it
            // can confirm, and a fanned hand is countable only sometimes —
            // greying this out turns a stall into a dead end.
            Button("Next") {
                if gameState.phase == .action { hasDeclaredActions = true } else { gameState.advance() }
            }
            .buttonStyle(RiftPrimaryButtonStyle())

            Button("Back") { gameState.back() }
                .buttonStyle(RiftSecondaryButtonStyle())
                .disabled(!gameState.canGoBack)

            Button("End Turn") {
                gameState.endTurn()
                hasDeclaredActions = false
            }
            .buttonStyle(RiftSecondaryButtonStyle())
            // Armed once the player says they're done, so the row reads as
            // a sequence rather than two live choices.
            .disabled(gameState.phase != .action || !hasDeclaredActions)
        }
    }

    // MARK: - Score

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score")
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)

            Text("Conquer and hold battlefields to get \(ScoreTracker.winningScore) points and win.")
                .font(RiftboundFont.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            ScoreTracker(playerScore: $playerScore, opponentScore: $opponentScore)
        }
    }

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
            } label: {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RiftboundPalette.regularText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded.wrappedValue ? "Collapse \(title)" : "Expand \(title)")
        }
    }
}
