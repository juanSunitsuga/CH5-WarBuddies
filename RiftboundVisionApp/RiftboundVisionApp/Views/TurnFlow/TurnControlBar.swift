//
//  TurnControlBar.swift
//  RiftboundVisionApp
//
//  Created by Anthony Martin Hasurungan on 19/08/26.
//

import SwiftUI
import RiftboundVision

/// Bottom bar: the three turn-stage cards, an "Auto-detect" toggle, and
/// the Next / End Turn buttons that move `ManualGameState` forward.
///
/// V3 restructures this bar. It used to be one line of phase prose plus
/// two buttons; it's now the phase map (`TurnPhasePanel`) plus a control
/// row. Everything the old bar *said* is still said — calibration
/// warnings, misplaced cards, `PhaseAutoDetector` progress, engine
/// verdicts and the standing ability list — it just moved into a status
/// strip above the cards that only appears when there's something to
/// report, rather than occupying a fixed line forever.
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
    /// What the current phase still needs from the player, from
    /// `PhaseAutoDetector`. During the fixed phases this replaces the
    /// static phase text with a live count — "1 of 2 runes channeled" —
    /// so the player can see the app registering what they do.
    var phaseProgress: PhaseAutoDetector.Progress?
    /// Cards sitting somewhere they can't be. Takes over the strip while
    /// any exist: the board and the engine have diverged, so telling the
    /// player what to put back matters more than the next turn step.
    var misplacedCards: [MisplacedCard] = []
    /// Most cards are landing outside every calibrated zone — the mat
    /// almost certainly doesn't line up with the camera.
    var needsCalibration = false

    /// The mockup's "START / Begin your turn." state — the moment before
    /// Awaken, where every pip is unlit and the gold button reads "Start
    /// Turn".
    ///
    /// Deliberately view-local rather than a new field on
    /// `ManualGameState`. It carries no rules meaning (nothing in 515
    /// distinguishes "at Awaken" from "about to be at Awaken") and the
    /// Expert System never reads it; it exists so the bottom row can show
    /// the two-step affordance the mockup draws. Reset whenever the seat
    /// changes, so the next player starts from START.
    @State private var hasStartedTurn = false

    /// Set when the player presses "Done Playing" — the declaration that
    /// arms End Turn.
    ///
    /// Like `hasStartedTurn` this is view-local and carries no rules
    /// meaning: 516.2 gives the Action Phase no completion condition, so
    /// nothing in `ManualGameState` or the Expert System can tell whether
    /// a player is finished. It exists so the bottom row reads as three
    /// sequential steps instead of two that light at once.
    @State private var hasDeclaredActions = false

    private var progress: RiftboundPhaseCopy.Progress {
        RiftboundPhaseCopy.Progress(
            hasStartedTurn: hasStartedTurn,
            phase: gameState.phase,
            hasDeclaredActions: hasDeclaredActions
        )
    }

    /// How long a verdict stays on screen before the strip returns to the
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
        .onChange(of: gameState.turnPlayer) { _, _ in
            hasStartedTurn = false
            hasDeclaredActions = false
        }
        // Stepping back out of the Action Phase (a new turn, or an
        // Auto-detect correction) un-declares — otherwise the row would
        // come back on the next turn already showing End Turn as live.
        .onChange(of: gameState.phase) { _, newPhase in
            if newPhase != .action { hasDeclaredActions = false }
        }
    }

    private func content(now: Date) -> some View {
        // Rule 516.2: only the Action Phase's contents are the player's to
        // choose, so it's the only phase where "was that allowed?" is a
        // question worth answering. During Awaken, Beginning, Channel and
        // Draw the player is carrying out a fixed script (515) — readying
        // cards, dealing runes — and reporting a verdict on each card they
        // touch while doing it buried the one line that told them what to
        // do under things like "Nothing to do for Chaos Rune."
        let recent = gameState.phase.validatesPlayerMoves
            ? instructions.filter { now.timeIntervalSince($0.timestamp) < Self.verdictLifetime }
            : []
        // Accepted and rejected are decisions about a move the player made;
        // the rest is commentary. Prefer a decision, then fall back to the
        // newest of anything.
        let recentInstruction = recent.first { $0.verdict == .accepted || $0.verdict == .rejected } ?? recent.first

        return VStack(alignment: .leading, spacing: 14) {
            phaseCards(recentInstruction)
            controlRow
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RiftboundPalette.mainBackground)
    }

    // MARK: - Status strip

    /// Same priority order the old single-line bar used, so nothing that
    /// could be said before goes unsaid now. Only rendered when there is
    /// something to say, so the row of cards isn't permanently pushed down
    /// by an empty slot — the plain phase instruction is the one case
    /// that's dropped, because the phase cards below already say it.
    @ViewBuilder
    private func statusStrip(_ recentInstruction: InstructionLogEntry?) -> some View {
        if needsCalibration {
            // Ranked above everything else: while this is true the
            // pipeline can't produce a verdict about anything, so a stale
            // one would be actively misleading.
            strip(
                icon: "square.dashed",
                tint: RiftboundPalette.highlightOverlay,
                headline: "Cards aren't landing on the mat.",
                detail: "Turn on Calibrate Playmat and drag the outline onto your mat — until then nothing can be read as a move."
            )
        } else if let misplaced = misplacedCards.first {
            strip(
                icon: "exclamationmark.triangle.fill",
                tint: RiftboundPalette.primaryButton,
                headline: "Put \(misplaced.label) back in the \(Self.name(misplaced.suggestedZone)).",
                detail: Self.reason(for: misplaced) + (misplacedCards.count > 1 ? "  ·  \(misplacedCards.count - 1) more misplaced." : "")
            )
        } else if let progress = phaseProgress, progress.needsCorrection {
            // Ranked above the engine's own verdict: this says the card on
            // the table can't be paid for and has to go back, which the
            // player must act on before anything the engine goes on to say
            // about it means much.
            strip(
                icon: "exclamationmark.triangle.fill",
                tint: RiftboundPalette.primaryButton,
                headline: progress.headline,
                detail: progress.detail,
                steps: progress.steps
            )
        } else if let latest = recentInstruction {
            strip(
                icon: latest.verdict.iconName,
                tint: latest.verdict.tint,
                headline: latest.headline,
                detail: latest.detail,
                steps: phaseProgress?.steps ?? []
            )
        } else if let progress = phaseProgress {
            // Live phase feedback. `isComplete` is the app saying it saw
            // the player finish, which is worth a different icon from a
            // step still outstanding — with Auto-detect on it's also the
            // last frame before the phase moves.
            strip(
                icon: progress.isComplete ? "checkmark.circle.fill" : "circle.dashed",
                tint: progress.isComplete ? RiftboundPalette.highlightOverlay : RiftboundPalette.elementStroke,
                headline: progress.headline,
                detail: progress.detail,
                steps: progress.steps
            )
        } else {
            // Before Start Game there is no pipeline and so no progress to
            // report, and this slot rendered as a blank rectangle of window
            // beside the phase cards. Saying what the phase expects fills
            // it with the one thing that's true either way, and means the
            // area never looks broken.
            strip(
                icon: "circle.dashed",
                tint: RiftboundPalette.elementStroke,
                headline: gameState.phase.instruction,
                detail: nil
            )
        }
    }

    private func strip(icon: String, tint: Color, headline: String, detail: String?, steps: [String] = []) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
                if let detail {
                    Text(detail)
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Abilities live on the board right now (base, battlefields,
                // legend). Shown under whatever the strip is saying rather
                // than instead of it — these are standing reminders, not
                // the current step, and a card's text is easy to forget
                // once it's been sitting there a few turns.
                if !steps.isEmpty {
                    ForEach(steps.prefix(3), id: \.self) { step in
                        Text("• \(step)")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                            .lineLimit(1)
                    }
                    if steps.count > 3 {
                        Text("+ \(steps.count - 3) more in play")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.45))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(RiftboundPalette.elementShadow.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.7), lineWidth: 1)
        )
    }

    // MARK: - Phase cards

    /// Centre-aligned, not top-aligned: `RiftPanelCard` stretches every
    /// card to the row's height, so the connecting hairlines belong on the
    /// shared midline rather than at a hand-guessed `.top` offset.
    /// The three stage cards, with whatever the app currently has to say
    /// filling the space to the right of End Turn.
    ///
    /// That space was a bare `Spacer` and the status strip sat above the
    /// cards, which pushed the whole row down whenever there was something
    /// to report and moved it back up when the message aged out — the
    /// bottom of the window shifted while a player was reading it. Putting
    /// the message beside End Turn instead uses ground that was already
    /// empty, and the row keeps one height whether or not anything is being
    /// said.
    private func phaseCards(_ recentInstruction: InstructionLogEntry?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            StartOfTurnPhaseCard(progress: progress)
            RiftFlowConnector()
            DoYourTurnCard(progress: progress)
            RiftFlowConnector()
            EndTurnCard(progress: progress)

            statusStrip(recentInstruction)
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $isAutoDetecting) {
                Text("Auto-detect")
                    .font(RiftboundFont.subheading)
                    .foregroundStyle(
                        isAutoDetecting
                            ? RiftboundPalette.highlightOverlay
                            : RiftboundPalette.regularText.opacity(0.7)
                    )
            }
            .toggleStyle(RiftSwitchToggleStyle())
            .fixedSize()

            // One live button at a time, matching the three cards above.
            //
            //   before the turn   → Start Turn
            //   A→B→C→D           → Next
            //   Action Phase      → Done Playing
            //   actions declared  → End Turn
            //
            // "Next" used to sit alongside End Turn during the Action
            // Phase doing exactly what End Turn did (516.6 puts nothing
            // after Action), which read as two different choices. Now each
            // step offers only the action that advances it.
            switch progress.stage {
            case .startOfTurn where !hasStartedTurn:
                Button("Start Turn") { hasStartedTurn = true }
                    .buttonStyle(RiftPrimaryButtonStyle())

            case .startOfTurn:
                // Auto-detect drives exactly this button, so it's the only
                // one the toggle disables.
                Button("Next") { gameState.advance() }
                    .buttonStyle(RiftPrimaryButtonStyle())
                    .disabled(isAutoDetecting)

            case .doYourTurn:
                Button("Done Playing") { hasDeclaredActions = true }
                    .buttonStyle(RiftPrimaryButtonStyle())

            case .endTurn:
                // **Never disabled.** 516.2 gives the Action Phase no
                // completion condition and 516.6 says it ends when the
                // player declares it, so nothing the camera sees can end a
                // turn. Greying this out under Auto-detect left the only
                // way out of the Action Phase unavailable.
                Button("End Turn") {
                    gameState.endTurn()
                    // `endTurn()` flips the seat, which fires the
                    // `onChange` above — set both here too so the row is
                    // right on this render pass rather than one frame later.
                    hasStartedTurn = false
                    hasDeclaredActions = false
                }
                .buttonStyle(RiftPrimaryButtonStyle())

                // An escape hatch: declaring "done" is a UI-only claim, so
                // taking it back has to be possible or a misclick strands
                // the player with no way to play the card they forgot.
                Button("Keep Playing") { hasDeclaredActions = false }
                    .buttonStyle(RiftSecondaryButtonStyle())
            }

            Spacer(minLength: 0)
        }
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
