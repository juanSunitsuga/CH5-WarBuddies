//
//  ActionTranslationEngine.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 07/08/26.
//

import Foundation

// MARK: - Activity Diagram Event & Action Models

public struct ObservedTableEvent {
    public let cardID: String
    /// The SQLite `card_id`, when the caller knows it. Distinct from
    /// `cardID` on purpose: callers coming from the vision pipeline key
    /// cards by `riftbound_id`, which shares no values with this
    /// database's hex ids. This is the reliable join key — it matches
    /// every row of the shipped database — and `cardName` is the looser
    /// fallback for callers that don't have it.
    public let databaseID: String?
    /// The card's printed name, when the caller knows it. Secondary join
    /// key — see `CardDatabaseService.fetchCard(named:)`.
    public let cardName: String?
    /// Printed rules text. Empty when the card couldn't be resolved to a
    /// known printing — that's a legitimate state (an unrecognized card
    /// still produces an event), not a reason to refuse to translate, so
    /// the engine falls back to metadata rather than requiring this.
    public let ocrText: String
    /// `nil` when the card's origin genuinely wasn't observed — a card
    /// that appeared already on the board, or whose track was lost and
    /// re-acquired. Deliberately NOT defaulted to `"Hand"`: assuming an
    /// unseen origin was the hand turns a missed observation into a
    /// confident, wrong "the player played this card" claim.
    public let sourceRegion: String?
    public let destinationRegion: String

    public init(
        cardID: String,
        databaseID: String? = nil,
        cardName: String? = nil,
        ocrText: String,
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

public enum CandidateGameAction {
    case playUnit(cardID: String, cardName: String, energyCost: Int, targetZone: String, mechanics: String)
    case castSpell(cardID: String, cardName: String, energyCost: Int, mechanics: String)
    case channelRune(cardID: String, cardName: String)
    case rejected(reason: String)
}

// MARK: - Step ② Engine Implementation

public final class ActionTranslatingEngine {
    
    private let embedderService = MiniLMEmbedderService()
    private let classifierService = CardTypeClassifierService()
    private let dbService = CardDatabaseService()
    
    public init() {}
    
    /// Step ②: Translates an ObservedTableEvent into a candidate GameAction.
    ///
    /// Resolution order matches the intended design: the SQLite database is
    /// the *primary* source (it already holds hand-verified type, cost, and
    /// tags), and the CoreML classifier is the *fallback* for cards the
    /// database doesn't know. The previous order — always classify first,
    /// then look up metadata — spent a CoreML embedding + classification on
    /// every event even when the database already held an authoritative
    /// answer, and let a model guess override known-good data.
    public func inferAction(event: ObservedTableEvent) async -> CandidateGameAction {

        // 1. Primary path: SQLite, most reliable key first — the caller's
        //    explicit database id, then the raw cardID (works when the
        //    caller already speaks this database's ID space), then the
        //    printed name as a last join attempt.
        let dbCard = event.databaseID.flatMap { dbService.fetchCard(by: $0) }
            ?? dbService.fetchCard(by: event.cardID)
            ?? event.cardName.flatMap { dbService.fetchCard(named: $0) }

        let cardType: String
        var cardName = "Unindexed Card"
        var energyCost = 0
        var extractedTags = "[]"

        if let dbCard {
            cardType = dbCard.cardType
            cardName = dbCard.cleanName
            energyCost = dbCard.energyCost
            extractedTags = dbCard.extractedTags
            print("💾 DB Hit: '\(cardName)' [\(cardType)] | Energy Cost: \(energyCost)")
        } else {
            // 2. Fallback path: classify from the printed text. Requires
            //    text — with neither a database row nor any text there is
            //    nothing to reason from, and guessing a type here would
            //    fabricate an action out of nothing.
            guard !event.ocrText.isEmpty else {
                return .rejected(reason: "Card '\(event.cardID)' is not in the database and has no printed text to classify.")
            }
            guard let vector = await embedderService.embed(text: event.ocrText) else {
                return .rejected(reason: "Failed to generate embedding vector from OCR text.")
            }
            guard let classification = classifierService.classify(embedding: vector) else {
                return .rejected(reason: "Card type classification failed.")
            }
            cardType = classification.cardType
            print("🧠 DB Miss -> Core ML Predicted Type: [\(cardType)] (\(String(format: "%.1f", classification.confidence * 100))% confidence)")

            // 3. Last resort for mechanics: regex over the raw text.
            //    (A FoundationModels tagging pass belongs between 2 and 3.)
            let parsed = SwiftRegexParser.parse(ocrText: event.ocrText)
            extractedTags = parsed.extractedTags
            if let name = event.cardName { cardName = name }
            print("⚡ Dynamic Swift Regex Parsed Tags: \(extractedTags)")
        }

        // 4. Early Heuristic Filter Logic (Type + Zone Validation)
        switch cardType {

        case "Unit":
            // An unobserved origin is not evidence of a play. Rejecting
            // with a specific reason (rather than assuming "Hand") keeps a
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
                return .rejected(reason: "Spells cannot be placed onto board zones as permanent objects.")
            }
            return .castSpell(
                cardID: event.cardID,
                cardName: cardName,
                energyCost: energyCost,
                mechanics: extractedTags
            )
            
        case "Rune":
            if event.destinationRegion == "RuneArea" {
                return .channelRune(cardID: event.cardID, cardName: cardName)
            } else {
                return .rejected(reason: "Runes must be played in the Rune Placement Area.")
            }
            
        default:
            return .rejected(reason: "Unhandled card type: \(cardType)")
        }
    }
}
