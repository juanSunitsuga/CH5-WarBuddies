import SwiftUI
import RiftboundVision

/// The bottom band: BonBon, and one line telling the player what to do.
///
/// This replaces the status strip that used to sit beside the phase cards.
/// The change is not only decorative — it's a decision about how much the
/// bar says at once. The strip carried a headline, a detail line and up to
/// four standing ability reminders, which meant the thing you needed *now*
/// competed with four things you might need later. Here there is one
/// sentence, at a size readable across a table, and the supporting detail
/// sits under it in a quieter weight.
///
/// The mascot is doing real work rather than decoration: it marks this band
/// as "the app talking to you", which is what lets the rest of the window
/// be purely the board and the controls.
struct MascotInstructionPanel: View {
    /// Recent verdicts from the Expert System, newest first.
    ///
    /// Taken as a list rather than just the newest because the pipeline
    /// emits one for *every* observed event: an accepted Play can be pushed
    /// off screen a fraction of a second later by a routine "came into view
    /// in the hand". A real verdict outranks an incidental one.
    var instructions: [InstructionLogEntry] = []
    /// What the current phase still needs, from `PhaseAutoDetector`.
    var progress: PhaseAutoDetector.Progress?
    /// Cards sitting somewhere they can't be.
    var misplacedCards: [MisplacedCard] = []
    /// Most cards are landing outside every calibrated zone.
    var needsCalibration = false
    /// Whether the app should be judging moves at all — only the Action
    /// Phase (516.2). During the fixed phases a verdict on every card the
    /// player touches while following a script buries the instruction.
    var validatesPlayerMoves = false
    /// Said when nothing else has anything to report, so the band is never
    /// empty — an empty speech panel reads as a broken one.
    var fallback: String

    /// How long a verdict stays up before the panel returns to the phase.
    /// Stale feedback is worse than none: it claims the app is keeping up
    /// when it isn't.
    private static let verdictLifetime: TimeInterval = 12

    /// What BonBon says, in priority order. Same ranking the status strip
    /// used, because the ordering is the part that was reasoned about:
    /// calibration first (nothing else can be trusted while it's wrong),
    /// then a misplaced card, then a play that can't be paid for, then the
    /// engine's verdict, then the phase.
    private func message(now: Date) -> (headline: String, detail: String?, isAlert: Bool) {
        if needsCalibration {
            return ("Cards aren't landing on the mat.",
                    "Turn on Calibrate Playmat and drag the outline onto your mat — until then nothing can be read as a move.",
                    true)
        }
        if let misplaced = misplacedCards.first {
            let more = misplacedCards.count > 1 ? "  ·  \(misplacedCards.count - 1) more misplaced." : ""
            return ("Put \(misplaced.label) back.",
                    "A \(misplaced.kind.rawValue) can't be there." + more,
                    true)
        }
        if let progress, progress.needsCorrection {
            return (progress.headline, progress.detail, true)
        }
        if validatesPlayerMoves {
            let recent = instructions.filter { now.timeIntervalSince($0.timestamp) < Self.verdictLifetime }
            if let latest = recent.first(where: { $0.verdict == .accepted || $0.verdict == .rejected }) ?? recent.first {
                return (latest.headline, latest.detail, latest.verdict == .rejected)
            }
        }
        if let progress {
            return (progress.headline, progress.detail, false)
        }
        return (fallback, nil, false)
    }

    var body: some View {
        // Re-evaluates once a second so a verdict can age out on its own,
        // without the controller scheduling a timer per instruction.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            panel(message(now: context.date))
        }
    }

    private func panel(_ message: (headline: String, detail: String?, isAlert: Bool)) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Image("BonBon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 132)
                // Decorative: everything BonBon "says" is the text beside
                // it, which VoiceOver already reads.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(message.headline.strippingRuleCitation)
                    .font(RiftboundFont.iconic2)
                    .foregroundStyle(message.isAlert ? RiftboundPalette.highlightOverlay : RiftboundPalette.iconicText)
                    .minimumScaleFactor(0.45)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = message.detail {
                    Text(detail.strippingRuleCitation)
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(RiftboundPalette.elementShadow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
        )
    }
}


private extension String {
    /// Strips a trailing rules citation like " (Rule 515.1)" or
    /// " (Rules 139.4, 157.2)" from `PhaseAutoDetector`/`CardAbilityParser`
    /// text. Those citations are for a maintainer cross-referencing the
    /// code against the rulebook — a player reading what BonBon says
    /// mid-game just wants the instruction. Stripped here, at the one place
    /// this panel renders any of that text, rather than at each of the
    /// dozen-plus call sites the citations actually live in — this reads on
    /// screen only, so the citations stay intact in the source (and in
    /// whatever tests assert on them) for the case they're useful there.
    var strippingRuleCitation: String {
        replacingOccurrences(of: #"\s\((?:Rule|Rules)\s[0-9][^)]*\)"#, with: "", options: .regularExpression)
    }
}

#Preview {
    VStack(spacing: 16) {
        MascotInstructionPanel(fallback: "Ready to play?")
        MascotInstructionPanel(
            progress: .init(
                headline: "You've played Tibbers.",
                detail: "Turn it sideways and exhaust 2 runes."
            ),
            fallback: "Ready to play?"
        )
    }
    .padding()
    .background(RiftboundPalette.mainBackground)
}
