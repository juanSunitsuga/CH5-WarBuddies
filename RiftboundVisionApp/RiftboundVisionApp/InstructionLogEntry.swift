import SwiftUI
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
    /// What the camera actually saw, phrased as a zone transition
    /// ("Hand → Battlefield"). Kept separate from `headline` so the log can
    /// show the *observation* and the *verdict* as two distinct columns —
    /// when they disagree, that difference is the whole debugging signal.
    let eventSummary: String
    let timestamp: Date

    /// The observation with no verdict attached — for events the pipeline
    /// saw but never ran the engine on (e.g. NLP translation switched off
    /// in the pipeline settings).
    init(unprocessed event: ObservedTableEvent, cardName: String?, reason: String) {
        verdict = .informational
        headline = reason
        detail = nil
        eventSummary = Self.summarize(event, card: cardName ?? "unidentified card")
        timestamp = Date()
    }

    /// `note` is the translator's out-of-band explanation for an event it
    /// understood but couldn't turn into a proposable action (see
    /// `ExpertSystemTranslatorAdapter.onUntranslatable`). Without it every
    /// such event reads as "couldn't tell what it meant," which is wrong
    /// for the common cases — a Battlefield being placed is perfectly
    /// understood, it just isn't a move.
    init(instruction: PlayerInstruction, cardName: String?, note: String? = nil, event: ObservedTableEvent? = nil) {
        let card = cardName ?? "an unidentified card"
        eventSummary = event.map { Self.summarize($0, card: cardName ?? "unidentified card") } ?? "—"
        timestamp = Date()

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
            if let note {
                // The translator did understand it — it just isn't a move.
                headline = "Nothing to do for \(card)."
                detail = note
            } else {
                headline = "Saw something move, but couldn't tell what it meant."
                detail = "Involving \(card)."
            }

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

    /// Renders the raw observation. `TableRegion` can only express Hand,
    /// Base, and Battlefield (rule 106.5.b), so a card entering the Rune
    /// Area or Trash never reaches this at all — if a physical move
    /// produces no log row, that gap is the first place to look.
    static func summarize(_ event: ObservedTableEvent, card: String) -> String {
        switch event.kind {
        case .cardAppeared(let region):
            return "\(card): appeared in \(name(region))"
        case .cardRemoved(let region):
            return "\(card): left \(name(region))"
        case .cardMoved(let from, let to):
            return "\(card): \(name(from)) → \(name(to))"
        case .cardOrientationChanged(let region, let nowExhausted):
            return "\(card): \(nowExhausted ? "exhausted" : "readied") in \(name(region))"
        }
    }

    private static func name(_ region: TableRegion) -> String {
        if region.isHandRegion { return "Hand" }
        switch region.nonLocationZone {
        case .runeArea: return "Rune Area"
        case .runeDeck: return "Rune Deck"
        case .mainDeck, .trash, .legend, .champion, nil: break
        }
        switch region.location {
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case nil: return "unknown zone"
        }
    }

    private static func describe(_ action: GameAction, card: String) -> String {
        switch action {
        case .play(_, let destination, _, _):
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
        case .recycleRune(let domain):
            return "Recycled a \(domain.rawValue.capitalized) rune."
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
        case .pass:
            return "Passed."
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
        case .insufficientPower(let required, let available):
            return "\(card) needs \(required) power from a matching Domain and you have \(available) recycled that qualify."
        case .exhaustedRuneCountMismatch(let required, let observed):
            return "\(card) needs \(required) rune\(required == 1 ? "" : "s") exhausted to pay for it, but \(observed) \(observed == 1 ? "is" : "are") exhausted."
        case .reactionRequired:
            return "\(card) can't respond right now — only Reaction cards can, while something else is already happening."
        case .actionOrReactionRequired:
            return "\(card) can't be played to open this Showdown — it needs the Action or Reaction keyword."
        case .limitedActionNotAuthorized:
            return "Nothing has called for that action yet — it can't be taken freely."
        case .notImplemented:
            return "The engine doesn't handle that action yet."
        }
    }
}

// MARK: - Presentation

/// Icon and tint for a verdict, defined once.
///
/// These were copy-pasted into both `TurnControlBar` and
/// `DetectedCardsPanel`, so the same verdict could drift to different
/// colours in two places on the same screen. Living on the type keeps them
/// in step and makes the compiler catch a new case.
extension InstructionLogEntry.Verdict {
    var iconName: String {
        switch self {
        case .accepted: return "checkmark.circle.fill"
        case .rejected: return "exclamationmark.triangle.fill"
        case .unrecognized: return "questionmark.circle.fill"
        case .informational: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .accepted: return .green
        case .rejected: return .orange
        case .unrecognized: return .yellow
        case .informational: return .cyan
        }
    }
}
