import SwiftUI
import RiftboundVision
import RiftboundTextProcessing

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
    /// The first pipeline stage that is switched off, if any. Ranked high
    /// because it changes what every other line here is worth: with the
    /// Expert System off, nothing below is being computed at all, and a
    /// band that just went quiet is indistinguishable from a broken one.
    var inactiveStage: String?
    /// Whether the app should be judging moves at all — only the Action
    /// Phase (516.2). During the fixed phases a verdict on every card the
    /// player touches while following a script buries the instruction.
    var validatesPlayerMoves = false
    /// The card the player has tapped, in the strip or on the camera
    /// overlay. `nil` when nothing is selected.
    var selectedCard: CardPrinting?
    /// Damage bonuses granted by cards already on the table, so a tapped
    /// card can be quoted at the number it will actually deal.
    var activeBonuses: [ActiveDamageBonus] = []
    /// Said when nothing else has anything to report, so the band is never
    /// empty — an empty speech panel reads as a broken one.
    var fallback: String

    /// How long a verdict stays up before the panel returns to the phase.
    /// Stale feedback is worse than none: it claims the app is keeping up
    /// when it isn't.
    private static let verdictLifetime: TimeInterval = 12

    /// One line for the band, and whether it still needs the plain-language
    /// pass run over it.
    private struct Message {
        var headline: String
        var detail: String?
        var isAlert: Bool
        /// `true` when the text arrived already worded for a player, so the
        /// renderer must leave it alone. Only the card summary sets it.
        var isFinal = false
    }

    /// What BonBon says, in priority order. Same ranking the status strip
    /// used, because the ordering is the part that was reasoned about:
    /// calibration first (nothing else can be trusted while it's wrong),
    /// then a misplaced card, then a play that can't be paid for, then the
    /// engine's verdict, then the phase.
    private func message(now: Date) -> Message {
        if let inactiveStage {
            return Message(
                headline: "\(inactiveStage) is switched off.",
                detail: "Turn it back on in Pipeline Settings and I'll read the table again. Until then the camera still shows the board, but nothing on it is being judged.",
                isAlert: true
            )
        }
        // A tap is the one message on this list the player *asked* for.
        // Everything below is the app volunteering something; this is it
        // answering a direct question, so it outranks the lot — with the
        // single exception above, because with the pipeline off the app
        // can't claim to know anything about the table.
        //
        // It outranks the corrections too, which looks aggressive until you
        // try it the other way: tapping a card during a calibration warning
        // then does nothing at all, and a button that does nothing reads as
        // broken. This is dismissable — tap the card again — and the
        // warning comes straight back, so nothing is lost, only deferred.
        if let selectedCard {
            return cardExplanation(selectedCard)
        }
        if needsCalibration {
            return Message(headline: "Cards aren't landing on the mat.", detail: "Turn on Calibrate Playmat and drag the outline onto your mat — until then nothing can be read as a move.", isAlert: true)
        }
        if let misplaced = misplacedCards.first {
            let more = misplacedCards.count > 1 ? "  ·  \(misplacedCards.count - 1) more misplaced." : ""
            return Message(
                headline: "Put \(misplaced.label) back.",
                detail: "A \(misplaced.kind.rawValue) can't be there." + more,
                isAlert: true
            )
        }
        if let progress, progress.needsCorrection {
            return Message(headline: progress.headline, detail: progress.detail, isAlert: true)
        }
        if validatesPlayerMoves {
            let recent = instructions.filter { now.timeIntervalSince($0.timestamp) < Self.verdictLifetime }
            if let latest = recent.first(where: { $0.verdict == .accepted || $0.verdict == .rejected }) ?? recent.first {
                return Message(
                    headline: latest.headline,
                    detail: latest.detail,
                    isAlert: latest.verdict == .rejected
                )
            }
        }
        if let progress {
            return Message(headline: progress.headline, detail: progress.detail, isAlert: false)
        }
        return Message(headline: fallback, detail: nil, isAlert: false)
    }

    /// What one card is, for a player who doesn't know it.
    ///
    /// The wording lives in `CardPlainLanguage.describeCard` so it can be
    /// tested without a running app; this is only the translation from a
    /// `CardPrinting` to the plain values it takes.
    private func cardExplanation(_ printing: CardPrinting) -> Message {
        let summary = CardPlainLanguage.describeCard(
            name: printing.name,
            type: printing.classification.type,
            energyCost: printing.attributes.energy,
            powerCost: printing.attributes.power ?? 0,
            powerDomains: printing.classification.domain,
            printedText: printing.text.plain,
            activeBonuses: activeBonuses
        )
        // `describeCard` has already run the plain-language pass. Saying so
        // is what stops the band running it a second time: a second pass
        // has a fresh gloss set, so it re-explains every term the first
        // pass already explained — "A token is a unit created during play."
        // twice — and it glosses the cost sentence this file generated,
        // which is how "Exhausted means turned sideways." ended up
        // explaining wording that came from us rather than from the card.
        return Message(headline: summary.headline, detail: summary.detail, isAlert: false, isFinal: true)
    }

    var body: some View {
        // Re-evaluates once a second so a verdict can age out on its own,
        // without the controller scheduling a timer per instruction.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            panel(message(now: context.date))
        }
    }

    private func panel(_ message: Message) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Image("BonBon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 132)
                // Decorative: everything BonBon "says" is the text beside
                // it, which VoiceOver already reads.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(message.isFinal ? message.headline : CardPlainLanguage.tidy(message.headline))
                    .font(RiftboundFont.iconic2)
                    .foregroundStyle(message.isAlert ? RiftboundPalette.highlightOverlay : RiftboundPalette.iconicText)
                    .minimumScaleFactor(0.45)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = message.detail {
                    Text(message.isFinal ? detail : CardPlainLanguage.simplify(detail))
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
