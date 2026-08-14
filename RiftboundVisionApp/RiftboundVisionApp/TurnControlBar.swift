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
    /// Newest verdict from the Expert System, if the pipeline has produced
    /// one — this is what makes the bar reflect what the camera actually
    /// saw rather than only the manually-set phase.
    var latestInstruction: InstructionLogEntry?
    /// Cards sitting somewhere they can't be. Takes over the bar while any
    /// exist: the board and the engine have diverged, so telling the player
    /// what to put back matters more than the next turn step.
    var misplacedCards: [MisplacedCard] = []

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                if let misplaced = misplacedCards.first {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Put \(misplaced.label) back in the \(Self.name(misplaced.suggestedZone)).")
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                    }
                    Text(Self.reason(for: misplaced) + (misplacedCards.count > 1 ? "  ·  \(misplacedCards.count - 1) more misplaced." : ""))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let latestInstruction {
                    HStack(spacing: 6) {
                        Image(systemName: latestInstruction.verdict.iconName)
                            .foregroundStyle(latestInstruction.verdict.tint)
                        Text(latestInstruction.headline)
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                    }
                    Text(latestInstruction.detail ?? gameState.phase.instruction)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Next Step")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(gameState.phase.instruction)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// Says what's wrong in the player's terms — the card's kind and where
    /// it is — rather than naming a rule.
    private static func reason(for card: MisplacedCard) -> String {
        "A \(card.kind.rawValue) can't be in the \(name(card.currentZone))."
    }

    private static func name(_ zone: Zone) -> String {
        switch zone {
        case .player1Hand, .player2Hand: return "Hand"
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case .runeArea: return "Rune Area"
        case .runeDeck: return "Rune Deck"
        case .mainDeck: return "Main Deck"
        case .trash: return "Trash"
        case .legend: return "Legend zone"
        case .champion: return "Champion zone"
        case .unknown: return "off-mat area"
        }
    }
}
