import SwiftUI
import RiftboundExpertSystem

/// One `PlayerInstruction` rendered for the screen — the last step of the
/// pipeline, where the Expert System's verdict becomes something a person
/// at the table can read. Keeping the rendering here (not in the engine)
/// keeps `RiftboundExpertSystem` free of presentation concerns, same
/// division as everywhere else in this app.
struct InstructionLogEntry: Identifiable {
    enum Verdict: Equatable {
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

    /// Renders the raw observation.
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

    /// Reads the region's `zone`, not its `location`.
    ///
    /// `location` is `nil` for everything that isn't a Base or Battlefield
    /// (rule 106), so once the Trash, the decks and the Rune Area became
    /// representable this rendered all six of them as "unknown zone" — a
    /// card going to the Trash read as "Base → unknown zone", which tells
    /// a player their move wasn't understood when it was.
    private static func name(_ region: TableRegion) -> String {
        switch region.zone {
        case .hand: return "Hand"
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case .mainDeck: return "Main Deck"
        case .runeDeck: return "Rune Deck"
        case .runeArea: return "Rune Area"
        case .trash: return "Trash"
        case .banishment: return "Banishment"
        case .legendZone: return "Legend zone"
        case .championZone: return "Champion zone"
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
            // `available` counts only pool entries of a Domain this card
            // accepts, so "you have 0" can be true with a full pool — say
            // "matching" rather than leaving the player counting runes.
            return "\(card) needs \(required) matching power and your pool has \(available). Recycle runes of a domain it accepts."
        case .exhaustedRuneCountMismatch(let required, let observed):
            return "\(card) costs \(required) energy, but \(observed) rune\(observed == 1 ? " was" : "s were") exhausted. Exhaust exactly \(required)."
        case .reactionRequired:
            return "Something is already resolving — only a Reaction can be played into it."
        case .actionOrReactionRequired:
            return "A showdown is open — only an Action or Reaction can start the chain."
        case .limitedActionNotAuthorized:
            return "Nothing has called for that action yet — it can't be taken freely."
        case .notActionPhase(let phase):
            return "You're still in \(name(phase)) — finish the start of your turn before playing."
        case .illegalMoveDestination(let from, let to):
            // 140.4: the two illegal shapes read very differently to a
            // player, so name the one they actually attempted rather than
            // reciting the whole rule.
            switch (from, to) {
            case (.battlefield, .battlefield):
                return "Units can't move straight between battlefields — send \(card) back to your base first (only Ganking skips that)."
            default:
                return "\(card) can't move there from where it is."
            }
        case .noRuneOfDomainAvailable(let domain):
            return "You have no \(domain.rawValue.capitalized) rune in your rune area to recycle."
        case .gameAlreadyWon:
            return "The game is already over."
        case .notImplemented:
            return "The engine doesn't handle that action yet."
        }
    }

    /// Phase names as a player would say them (rule 514–517).
    private static func name(_ phase: Phase) -> String {
        switch phase {
        case .startOfTurn(.awaken):    return "the awaken step"
        case .startOfTurn(.beginning): return "the beginning phase"
        case .startOfTurn(.channel):   return "the channel phase"
        case .startOfTurn(.draw):      return "the draw phase"
        case .action:                  return "the action phase"
        case .endOfTurn:               return "the end of your turn"
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

    /// Mapped onto the design board rather than onto semantic system
    /// colours.
    ///
    /// Worth being explicit about the compromise: the board has no error
    /// colour. Nothing in the eleven swatches reads as "this is wrong",
    /// so `rejected` uses the deepest, most saturated gold available and
    /// leans on `iconName`'s warning triangle to carry the meaning. That's
    /// weaker than a red would be, and it's the one place the palette is
    /// doing less work than the UI needs — flagged rather than papered
    /// over with an off-board hex.
    var tint: Color {
        switch self {
        case .accepted: return RiftboundPalette.highlightOverlay
        case .rejected: return RiftboundPalette.primaryButton
        case .unrecognized: return RiftboundPalette.elementStroke
        case .informational: return RiftboundPalette.iconicText
        }
    }
}
