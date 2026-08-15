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
    /// Recent verdicts from the Expert System, newest first.
    ///
    /// The bar takes the list rather than just the newest because the
    /// pipeline emits an instruction for *every* observed event: an
    /// accepted Play could be pushed off screen a fraction of a second
    /// later by a routine "came into view in the hand". The thing a player
    /// needs to see is whether their move was allowed, so a real verdict
    /// outranks an incidental one within the same window.
    var instructions: [InstructionLogEntry] = []
    /// Cards sitting somewhere they can't be. Takes over the bar while any
    /// exist: the board and the engine have diverged, so telling the player
    /// what to put back matters more than the next turn step.
    var misplacedCards: [MisplacedCard] = []
    /// Most cards are landing outside every calibrated zone — the mat
    /// almost certainly doesn't line up with the camera.
    var needsCalibration = false

    /// How long a verdict stays on screen before the bar returns to the
    /// phase instruction.
    ///
    /// Without this the newest verdict was shown forever: minutes after a
    /// play the bar still read "Played Tibbers to the Battlefield," which a
    /// player reasonably reads as a statement about *now*. Stale feedback
    /// is worse than none — it says the app is keeping up when it isn't.
    /// A misplaced card is exempt, since that condition persists until the
    /// card is physically moved back.
    private static let verdictLifetime: TimeInterval = 12

    var body: some View {
        // Re-evaluates once a second so a verdict can age out on its own,
        // without the controller having to schedule a timer per instruction.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let recent = instructions.filter { now.timeIntervalSince($0.timestamp) < Self.verdictLifetime }
        // Accepted and rejected are decisions about a move the player made;
        // the rest is commentary. Prefer a decision, then fall back to the
        // newest of anything.
        let recentInstruction = recent.first { $0.verdict == .accepted || $0.verdict == .rejected } ?? recent.first

        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                if needsCalibration {
                    // Ranked above everything else: while this is true the
                    // pipeline can't produce a verdict about anything, so a
                    // stale one would be actively misleading.
                    HStack(spacing: 6) {
                        Image(systemName: "square.dashed")
                            .foregroundStyle(.yellow)
                        Text("Cards aren't landing on the mat.")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    Text("Turn on Calibrate Playmat and drag the outline onto your mat — until then nothing can be read as a move.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let misplaced = misplacedCards.first {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Put \(misplaced.label) back in the \(Self.name(misplaced.suggestedZone)).")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    Text(Self.reason(for: misplaced) + (misplacedCards.count > 1 ? "  ·  \(misplacedCards.count - 1) more misplaced." : ""))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let latestInstruction = recentInstruction {
                    HStack(spacing: 6) {
                        Image(systemName: latestInstruction.verdict.iconName)
                            .foregroundStyle(latestInstruction.verdict.tint)
                        Text(latestInstruction.headline)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    Text(latestInstruction.detail ?? gameState.phase.instruction)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Next Step")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(gameState.phase.instruction)
                        .font(.title3)
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
        .padding(.vertical, 18)
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
