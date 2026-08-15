//
//  ActionTranslationEngine.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 07/08/26.
//

import Foundation
import SwiftData

// MARK: - Activity Diagram Event & Action Models

/// Flat, text-processing DTO describing a physical board move as seen by the
/// vision layer. Distinct from `RiftboundExpertSystem.ObservedTableEvent`:
/// this one carries the raw OCR payload the tagging/regex fallback needs.
public struct ObservedTableEvent: Sendable {
    public let cardID: String
    /// The card catalogue's own `card_id`, when the caller knows it.
    /// Distinct from `cardID` on purpose: callers coming from the vision
    /// pipeline key cards by `riftbound_id` (`ogn-007-298`), which shares
    /// no values with this database's hex ids
    /// (`69bc5bc6d308c64675ca86bc`). This is the reliable join key — it
    /// matches every row of the shipped database — and `cardName` is the
    /// looser fallback for callers that don't have it.
    public let databaseID: String?
    /// The card's printed name, when the caller knows it. Secondary join
    /// key — see `CardDatabaseService.fetchCard(named:)`.
    public let cardName: String?
    /// Printed rules text. Empty when the card couldn't be resolved to a
    /// known printing — a legitimate state (an unrecognized card still
    /// produces an event), not a reason to refuse to translate, so the
    /// engine falls back to its own lookups rather than requiring this.
    public let ocrText: String
    /// `nil` when the card's origin genuinely wasn't observed — a card that
    /// appeared already on the board, or whose track was lost and
    /// re-acquired. Deliberately NOT defaulted to `"Hand"`: assuming an
    /// unseen origin was the hand turns a missed observation into a
    /// confident, wrong "the player played this card" claim.
    public let sourceRegion: String?
    public let destinationRegion: String

    public init(
        cardID: String,
        databaseID: String? = nil,
        cardName: String? = nil,
        ocrText: String = "",
        sourceRegion: String?,
        destinationRegion: String
    ) {
        self.cardID = cardID
        self.databaseID = databaseID
        self.cardName = cardName
        self.ocrText = ocrText
        self.sourceRegion = sourceRegion
        self.destinationRegion = destinationRegion
    }
}

/// Candidate action inferred from an `ObservedTableEvent`, before legality
/// validation by the expert system.
public enum CandidateGameAction: Equatable, Sendable {
    case playUnit(cardID: String, cardName: String, energyCost: Int, targetZone: String, mechanics: String)
    case castSpell(cardID: String, cardName: String, energyCost: Int, mechanics: String)
    case channelRune(cardID: String, cardName: String)
    /// Rule 130.3: a Rune observed moving back to the Rune Deck — paying a
    /// Power cost, the reverse physical direction of `channelRune`.
    case recycleRune(cardID: String, cardName: String)
    case rejected(reason: String)
}

public final class ActionTranslatingEngine: @unchecked Sendable {

    // Created lazily on the main actor: `SwiftDataCardService` is
    // `@MainActor`-isolated, so it can't be initialized from this class's
    // nonisolated `init()`. Optional `var` defaults to nil without needing
    // main-actor context; `dataService()` builds it once on first use.
    @MainActor private var swiftDataService: SwiftDataCardService?
    /// Read directly (not only through SwiftData) so a lookup can fall back
    /// to the name join and to the bundled `plain_text` column.
    private let sqliteService = CardDatabaseService()

    public init() {}

    @MainActor
    private func dataService() -> SwiftDataCardService {
        if let existing = swiftDataService { return existing }
        let service = SwiftDataCardService()
        service.seedFromBundledDatabase()
        swiftDataService = service
        return service
    }

    /// Both lookups in one main-actor hop. `SwiftDataCardService` is
    /// `@MainActor`-isolated, so each individual `fetchCard` would
    /// otherwise need its own `await` — and an `await` outside a closure
    /// doesn't cover the calls made inside it.
    @MainActor
    private func swiftDataCard(for event: ObservedTableEvent) -> RiftboundCard? {
        let service = dataService()
        return event.databaseID.flatMap { service.fetchCard(by: $0) }
            ?? service.fetchCard(by: event.cardID)
    }

    @MainActor
    private func cache(_ card: RiftboundCard) {
        dataService().saveCard(card)
    }

    /// Step ②: translate an `ObservedTableEvent` into a candidate action.
    ///
    /// Resolution order, most authoritative first:
    ///   1. SwiftData (seeded from the bundled SQLite database, plus
    ///      anything the Foundation Model has tagged and cached).
    ///   2. SQLite directly, by name — catches cards SwiftData missed
    ///      because the caller's ID is in a different ID space.
    ///   3. On-device Foundation Model tagging, whose result is cached back
    ///      into SwiftData so the same card resolves at step 1 next time.
    ///   4. Swift regex, for older OS versions or a model error.
    ///
    /// Steps 3–4 need text; if the caller didn't supply any, the bundled
    /// database's own `plain_text` column is used, which means an
    /// unrecognized card is still translatable as long as *something*
    /// knows its text.
    public func inferAction(event: ObservedTableEvent) async -> CandidateGameAction {

        var cardName = event.cardName ?? "Unindexed Card"
        var cardType = "Unknown"
        var energyCost = 0
        var extractedTags = "[]"

        // 1. PRIMARY PATH: SwiftData lookup (<0.05ms). Tries the caller's
        //    explicit database id first, then the raw cardID.
        let swiftDataCard = await swiftDataCard(for: event)

        // 2. Still nothing? Fall back to a direct SQLite name join. The
        //    vision pipeline's `riftbound_id` never matches this database's
        //    hex `card_id`, so without a name this is the only key left.
        let sqliteCard = swiftDataCard == nil
            ? event.cardName.flatMap { sqliteService.fetchCard(named: $0) }
            : nil

        if let swiftDataCard {
            cardName = swiftDataCard.cleanName
            cardType = swiftDataCard.cardType
            energyCost = swiftDataCard.energyCost
            extractedTags = "[\(swiftDataCard.extractedTags.joined(separator: ", "))]"
            print("💾 SwiftData Hit: '\(cardName)' (\(cardType))")

        } else if let sqliteCard {
            cardName = sqliteCard.cleanName
            cardType = sqliteCard.cardType
            energyCost = sqliteCard.energyCost
            extractedTags = sqliteCard.extractedTags
            print("💾 SQLite Name Hit: '\(cardName)' (\(cardType))")

        } else {
            // Prefer the caller's text, but fall back to the bundled
            // database's own copy — the caller having no text doesn't mean
            // nothing does.
            let text = event.ocrText.isEmpty
                ? (event.databaseID.flatMap { sqliteService.printedText(for: $0) } ?? "")
                : event.ocrText

            guard !text.isEmpty else {
                return .rejected(reason: "Card '\(event.cardID)' isn't in the database and has no printed text to tag.")
            }

            // 3. FALLBACK PATH: on-device Foundation Model tagging.
            if #available(iOS 26.0, macOS 26.0, *) {
                print("🤖 Running On-Device Foundation Model Tagging...")
                let foundationService = FoundationModelTaggingService()

                do {
                    let taggedCard = try await foundationService.tagCardText(text)
                    cardType = taggedCard.cardType
                    energyCost = taggedCard.energyCost
                    extractedTags = "[\(taggedCard.extractedTags.joined(separator: ", "))]"

                    // Cache under the id this event will actually present
                    // next time, otherwise the same card misses step 1
                    // forever and pays for tagging on every observation.
                    taggedCard.cardID = event.databaseID ?? event.cardID
                    taggedCard.cleanName = cardName
                    await cache(taggedCard)
                    print("✨ Tagged & Saved via Foundation Model: Type [\(cardType)], Cost [\(energyCost)]")
                } catch {
                    print("⚠️ Foundation Model Error: \(error). Falling back to Regex...")
                    extractedTags = SwiftRegexParsingService.parse(ocrText: text).extractedTags
                }
            } else {
                // 4. Older OS / unsupported: fast Swift regex parser.
                print("⚡ Older OS detected -> Falling back to Swift Regex Parser...")
                extractedTags = SwiftRegexParsingService.parse(ocrText: text).extractedTags
            }
        }

        // 5. Early Heuristic Filter Logic
        switch cardType {
        case "Unit":
            // An unobserved origin is not evidence of a play. Rejecting with
            // a specific reason (rather than assuming "Hand") keeps a
            // dropped track from being reported as a confident play.
            guard let sourceRegion = event.sourceRegion else {
                return .rejected(reason: "Didn't observe where this Unit came from, so it can't be confirmed as played from hand.")
            }
            if sourceRegion == "Hand" && (event.destinationRegion == "Base" || event.destinationRegion == "Battlefield") {
                return .playUnit(
                    cardID: event.cardID,
                    cardName: cardName,
                    energyCost: energyCost,
                    targetZone: event.destinationRegion,
                    mechanics: extractedTags
                )
            } else {
                return .rejected(reason: "Units can only be played from Hand to Base or Battlefield.")
            }

        case "Spell":
            if event.destinationRegion == "Battlefield" || event.destinationRegion == "Base" {
                return .rejected(reason: "Spells cannot be placed onto board zones.")
            }
            return .castSpell(
                cardID: event.cardID,
                cardName: cardName,
                energyCost: energyCost,
                mechanics: extractedTags
            )

        case "Rune":
            switch event.destinationRegion {
            case "RuneArea":
                return .channelRune(cardID: event.cardID, cardName: cardName)
            case "RuneDeck":
                return .recycleRune(cardID: event.cardID, cardName: cardName)
            default:
                return .rejected(reason: "Runes must be Channeled to the Rune Area or Recycled back to the Rune Deck.")
            }

        case "Battlefield", "Legend":
            // Rule 052/106: Battlefields and Legends are Game Objects but
            // explicitly *not* Main Deck cards — they're placed during
            // setup and stay put, so seeing one move is never a Play. This
            // is a real answer ("that isn't an action"), not a parse
            // failure; without the case they fell to `default` and the app
            // reported the far more alarming "couldn't tell what it meant."
            return .rejected(reason: "\(cardName) is a \(cardType) — placed during setup, not played as an action.")

        default:
            return .rejected(reason: "Unhandled card type: \(cardType)")
        }
    }
}
