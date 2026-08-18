//
//  TurnPhasePanel.swift
//  RiftboundVisionApp
//
//  Created by Anthony Martin Hasurungan on 19/08/26.
//

import SwiftUI
import RiftboundVision

/// The bottom row of V3: three linked cards that say where you are in the
/// turn — "Start of Turn Phases", "Do Your Turn!", "End Turn".
///
/// Written against the *five*-phase `GamePhase`. Rule 517's Ending,
/// Expiration and Cleanup steps were deliberately removed from that enum
/// (see its doc comment: they contain nothing a player at the table
/// actually does), so "End Turn" here is not a phase you land in — it's
/// the thing you press *from* the Action Phase. The third card is a
/// destination marker, and it lights up when the Action Phase is live
/// because that is the moment the button becomes available.

// MARK: - Copy

/// Short, table-facing wording for each phase, kept here in the app layer
/// rather than added to `GamePhase` in the `RiftboundVision` package.
///
/// The package deliberately mirrors the Expert System's rules vocabulary;
/// presentation copy that says "Ready all units and runes" instead of
/// "Ready all Game Objects controlled by Turn Player" belongs on this side
/// of that line, the same way `InstructionLogEntry` keeps verdict
/// rendering out of the engine.
///
/// `GamePhase.instruction` is the fuller, rule-cited version of the same
/// thing and is still shown — as the tooltip on each card, and by
/// `TurnControlBar` whenever there's no live `PhaseAutoDetector` progress
/// to show instead.
enum RiftboundPhaseCopy {
    /// Which of the three cards is lit for a phase.
    enum Stage {
        case startOfTurn
        case doYourTurn
    }

    static func stage(for phase: GamePhase) -> Stage {
        switch phase {
        case .awaken, .beginning, .channel, .draw: return .startOfTurn
        case .action: return .doYourTurn
        }
    }

    /// The four lettered start-of-turn steps, in order — A, B, C, D on the
    /// pips. Rule 515's fixed script.
    static let startOfTurnPhases: [GamePhase] = [.awaken, .beginning, .channel, .draw]

    static func pipLetter(for phase: GamePhase) -> String {
        guard let index = startOfTurnPhases.firstIndex(of: phase) else { return "" }
        return String(UnicodeScalar(65 + index)!)
    }

    /// Uppercase name shown under the pips.
    static func title(for phase: GamePhase) -> String {
        phase.displayName.uppercased()
    }

    /// One line, plain language, no rule numbers.
    static func blurb(for phase: GamePhase) -> String {
        switch phase {
        case .awaken: return "Ready all units and runes."
        case .beginning: return "Get Hold points from battlefields."
        case .channel: return "Channel 2 runes."
        case .draw: return "Draw 1 card."
        case .action: return "Play cards and move your units."
        }
    }
}

// MARK: - Pip

/// One lettered step marker. Three appearances, all from the board:
/// completed-or-current is `highlightOverlay`, still-to-come is
/// `elementShadow`, and not-applicable-yet is `disabledHighlightOverlay`.
///
/// Note this is a *colour* change, not an opacity one — an upcoming pip
/// lives inside a card that is itself active, and the board's rule is that
/// 50% dimming applies only when the whole component is off.
struct TurnPhasePip: View {
    /// Named `Appearance` rather than `State` on purpose — a nested type
    /// called `State` shadows SwiftUI's property wrapper inside this
    /// type's scope, which turns a later `@State var` here into a
    /// baffling compile error.
    enum Appearance {
        case reached
        case upcoming
        case inactive
    }

    let letter: String
    let state: Appearance

    var body: some View {
        Text(letter)
            .font(RiftboundFont.heading)
            .foregroundStyle(state == .reached ? RiftboundPalette.elementShadow : RiftboundPalette.regularText)
            .frame(width: 34, height: 34)
            .background(Circle().fill(fill))
            .accessibilityLabel("Step \(letter)")
            .accessibilityValue(accessibilityValue)
    }

    private var fill: Color {
        switch state {
        case .reached: return RiftboundPalette.highlightOverlay
        case .upcoming: return RiftboundPalette.elementShadow
        case .inactive: return RiftboundPalette.disabledHighlightOverlay
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .reached: return "done or current"
        case .upcoming: return "still to come"
        case .inactive: return "not started"
        }
    }
}

// MARK: - Card 1

struct StartOfTurnPhaseCard: View {
    let phase: GamePhase
    /// False before the player has pressed "Start Turn" — the mockup's
    /// "START / Begin your turn." state, with every pip unlit.
    let hasStartedTurn: Bool

    private var isActive: Bool {
        hasStartedTurn && RiftboundPhaseCopy.stage(for: phase) == .startOfTurn
    }

    var body: some View {
        RiftPanelCard(isActive: isActive) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Start of Turn Phases")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(isActive ? RiftboundPalette.highlightOverlay : RiftboundPalette.regularText)

                // The reference links the pips with the same hairline it
                // uses between the cards, so the four steps read as one
                // run rather than four separate badges.
                HStack(spacing: 0) {
                    ForEach(Array(RiftboundPhaseCopy.startOfTurnPhases.enumerated()), id: \.element) { index, step in
                        if index > 0 {
                            RiftFlowConnector(length: 10)
                        }
                        TurnPhasePip(letter: RiftboundPhaseCopy.pipLetter(for: step), state: pipState(for: step))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isActive ? RiftboundPhaseCopy.title(for: phase) : "START")
                        .font(RiftboundFont.heading)
                        .foregroundStyle(isActive ? RiftboundPalette.highlightOverlay : RiftboundPalette.regularText)
                    Text(isActive ? RiftboundPhaseCopy.blurb(for: phase) : "Begin your turn.")
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .riftComponentDisabled(!isActive)
        .help(isActive ? phase.instruction : "Press Start Turn to begin.")
    }

    private func pipState(for step: GamePhase) -> TurnPhasePip.Appearance {
        guard isActive,
              let current = RiftboundPhaseCopy.startOfTurnPhases.firstIndex(of: phase),
              let index = RiftboundPhaseCopy.startOfTurnPhases.firstIndex(of: step) else {
            return .inactive
        }
        return index <= current ? .reached : .upcoming
    }
}

// MARK: - Card 2

struct DoYourTurnCard: View {
    let phase: GamePhase
    let hasStartedTurn: Bool

    private var isActive: Bool {
        hasStartedTurn && RiftboundPhaseCopy.stage(for: phase) == .doYourTurn
    }

    var body: some View {
        RiftPanelCard(isActive: isActive) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Do Your Turn!")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(isActive ? RiftboundPalette.highlightOverlay : RiftboundPalette.regularText)

                // Chip heights measured off the reference rather than
                // taken from the SVGs' native sizes: the mockup draws the
                // portrait chips at 44pt tall (native 53) and the
                // Battlefield at 32pt (native 38). Widths follow from
                // `scaledToFit`, so the art keeps its own proportions.
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            chip(RiftboundArt.unit(active: isActive), height: Self.portraitChipHeight)
                            chip(RiftboundArt.spell(active: isActive), height: Self.portraitChipHeight)
                        }
                        Text("Play cards from hand.")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        // A Unit tucked over the right edge of a
                        // Battlefield — the overlap *is* the idea being
                        // shown (a unit standing on a battlefield). In the
                        // reference the two chips share a top edge and
                        // overlap by about 5pt, with the Unit drawn last
                        // so it sits on top.
                        HStack(alignment: .top, spacing: -5) {
                            chip(RiftboundArt.battlefield(active: isActive), height: Self.landscapeChipHeight)
                            chip(RiftboundArt.unit(active: isActive), height: Self.portraitChipHeight)
                        }
                        Text("Conquer and combat the battlefield with your units.")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                }
            }
        }
        .riftComponentDisabled(!isActive)
        .help(GamePhase.action.instruction)
    }

    /// Unit and Spell.
    private static let portraitChipHeight: CGFloat = 44
    /// Battlefield.
    private static let landscapeChipHeight: CGFloat = 32

    private func chip(_ asset: String, height: CGFloat) -> some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Card 3

/// The turn's destination.
///
/// Unlike the other two this card marks no phase — 517's steps aren't in
/// `GamePhase` at all. It lights up during the Action Phase because 516.6
/// says the turn ends when the player declares it, so that's exactly when
/// the End Turn button below becomes the live action. Treating it as a
/// signpost rather than a step is what keeps the row honest about a
/// five-phase model.
struct EndTurnCard: View {
    let phase: GamePhase
    let hasStartedTurn: Bool

    private var isActive: Bool {
        hasStartedTurn && RiftboundPhaseCopy.stage(for: phase) == .doYourTurn
    }

    var body: some View {
        RiftPanelCard(isActive: isActive, alignment: .center) {
            Text("End Turn")
                .font(RiftboundFont.heading)
                .foregroundStyle(isActive ? RiftboundPalette.highlightOverlay : RiftboundPalette.regularText)
                .frame(minWidth: 96)
        }
        .riftComponentDisabled(!isActive)
        .help(isActive
              ? "Ending the Action Phase runs the rest of the turn and passes to the other seat (Rule 516.6/517)."
              : "Available once you reach your Action Phase.")
    }
}

#Preview {
    HStack(spacing: 0) {
        StartOfTurnPhaseCard(phase: .beginning, hasStartedTurn: true)
        RiftFlowConnector()
        DoYourTurnCard(phase: .beginning, hasStartedTurn: true)
        RiftFlowConnector()
        EndTurnCard(phase: .beginning, hasStartedTurn: true)
    }
    .padding()
    .background(RiftboundPalette.mainBackground)
}
