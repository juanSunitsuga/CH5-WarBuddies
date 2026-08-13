import Foundation
import RiftboundExpertSystem

/// One `PlayerInstruction` rendered for the screen — the last step of the
/// pipeline, where the Expert System's verdict becomes something a person
/// at the table can read. Keeping the rendering here (not in the engine)
/// keeps `RiftboundExpertSystem` free of presentation concerns, same
/// division as everywhere else in this app.
struct InstructionLogEntry: Identifiable {
    enum Verdict {
        case accepted
        case rejected
        case unrecognized
        case informational
    }

    let id = UUID()
    let verdict: Verdict
    let headline: String
    let detail: String?

    init(instruction: PlayerInstruction, cardName: String?) {
        let card = cardName ?? "an unidentified card"

        switch instruction {
        case .actionAccepted(let action, let followUp):
            verdict = .accepted
            headline = Self.describe(action, card: card)
            detail = followUp?.description

        case .actionRejected(_, let reason):
            verdict = .rejected
            headline = "That move isn't legal right now."
            detail = Self.describe(reason, card: card)

        case .unrecognizedEvent:
            verdict = .unrecognized
            headline = "Saw something move, but couldn't tell what it meant."
            detail = "Involving \(card)."

        case .choiceRequired(let prompt):
            verdict = .informational
            headline = prompt.prompt
            detail = "\(prompt.options.count) option\(prompt.options.count == 1 ? "" : "s") to choose from."

        case .scored(_, _, let newTotal):
            verdict = .informational
            headline = "Scored a point."
            detail = "New total: \(newTotal)."

        case .gameWon:
            verdict = .informational
            headline = "That's the game — you win."
            detail = nil
        }
    }

    private static func describe(_ action: GameAction, card: String) -> String {
        switch action {
        case .play(_, let destination, _):
            switch destination {
            case .base: return "Played \(card) to your Base."
            case .battlefield: return "Played \(card) to the Battlefield."
            case .none: return "Played \(card)."
            }
        case .standardMove(let units, let destination):
            let subject = units.count == 1 ? card : "\(units.count) units"
            switch destination {
            case .base: return "Moved \(subject) back to your Base."
            case .battlefield: return "Moved \(subject) to the Battlefield."
            }
        case .draw(let count):
            return "Drew \(count) card\(count == 1 ? "" : "s")."
        case .channel(let count, _):
            return "Channeled \(count) rune\(count == 1 ? "" : "s")."
        case .exhaust:
            return "Exhausted \(card)."
        case .ready:
            return "Readied \(card)."
        case .discard:
            return "Discarded \(card)."
        case .kill:
            return "\(card) was killed."
        case .banish:
            return "\(card) was banished."
        case .endTurn:
            return "Turn ended."
        default:
            return "Action accepted."
        }
    }

    /// Rejection reasons, phrased as what the player should do about it
    /// rather than as the validator's internal case name.
    private static func describe(_ failure: LegalityValidator.Failure, card: String) -> String {
        switch failure {
        case .notPlayersPriority:
            return "It isn't your turn to act, or the board is mid-resolution."
        case .unitAlreadyExhausted:
            return "\(card) is already exhausted — ready it before moving again."
        case .unitNotFound:
            return "That unit isn't on the board as far as the engine can tell."
        case .destinationOccupiedByTwoOtherControllers:
            return "That battlefield already has units from two other players."
        case .moveOriginsMismatch:
            return "Those units can't move together from where they are."
        case .cardNotInHand:
            return "\(card) isn't in your hand — it may already have been played."
        case .invalidPlayDestination:
            return "\(card) can't be played there."
        case .insufficientEnergy(let required, let available):
            return "\(card) costs \(required) energy and you have \(available)."
        case .limitedActionNotAuthorized:
            return "Nothing has called for that action yet — it can't be taken freely."
        case .notImplemented:
            return "The engine doesn't handle that action yet."
        }
    }
}
