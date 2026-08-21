import SwiftUI
import RiftboundVision

/// Player-facing names and copy for the turn's phases.
///
/// Was the backing for a row of phase cards under the camera. The V4 layout
/// moved the turn controls into the right-hand column, so the cards are
/// gone and this is what outlived them — the naming is still shared, by the
/// pips and the phase blurb in `TurnControlColumn`.
enum RiftboundPhaseCopy {
    /// Which of the three cards is lit.
    ///
    /// Not derivable from `GamePhase` alone. The five phases end at
    /// `.action`, but the row draws *three* stages, because "End Turn" is
    /// a thing the player does at the end of the Action Phase rather than
    /// a phase of its own (516.6). So the last two share `.action` and are
    /// told apart by `hasDeclaredActions` — see `Progress` below.
    enum Stage {
        case startOfTurn
        case doYourTurn
        case endTurn
    }

    /// Where the player is in the turn, as the bottom row sees it.
    ///
    /// Three flags rather than one enum because they're independent facts
    /// that arrive from different places: the turn being started is a UI
    /// affordance, the phase comes from the engine, and finishing your
    /// actions is a declaration only the player can make.
    struct Progress {
        /// Pressed "Start Turn" — before this, every card is unlit and the
        /// first card reads "START / Begin your turn."
        var hasStartedTurn: Bool
        /// Reached the Action Phase by stepping A→B→C→D.
        var phase: GamePhase
        /// Declared they're done playing cards, which is what arms the
        /// End Turn button.
        var hasDeclaredActions: Bool

        var stage: Stage {
            guard hasStartedTurn else { return .startOfTurn }
            switch phase {
            case .awaken, .beginning, .channel, .draw: return .startOfTurn
            case .action: return hasDeclaredActions ? .endTurn : .doYourTurn
            }
        }
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

    /// The phase's description, in plain language and with no rule numbers.
    ///
    /// Deliberately *static* — one fixed sentence per phase, not a line
    /// that reacts to the table. `GamePhase.instruction` is the reactive,
    /// rule-cited text the engine reasons with, and putting that in front
    /// of a player meant the description under the pips rewrote itself
    /// mid-phase and cited rulebook sections at someone who is holding
    /// cards. What belongs here is the answer to "what is this phase for",
    /// which never changes.
    static func blurb(for phase: GamePhase) -> String {
        switch phase {
        case .awaken: return "Ready all units and runes."
        case .beginning: return "Get Hold points from battlefield."
        case .channel: return "Play 2 runes from the Rune deck."
        case .draw: return "Draw 1 card from the Main deck."
        case .action: return "Play cards from hand. Conquer and combat the battlefield with your units."
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
