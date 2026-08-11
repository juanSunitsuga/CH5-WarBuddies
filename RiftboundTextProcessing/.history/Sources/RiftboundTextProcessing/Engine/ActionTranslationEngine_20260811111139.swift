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
    public let ocrText: String
    public let sourceRegion: String
    public let destinationRegion: String
    
    public init(cardID: String, ocrText: String, sourceRegion: String, destinationRegion: String) {
        self.cardID = cardID
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
    
    /// Step ②: Translates an ObservedTableEvent into a candidate GameAction
    public func inferAction(event: ObservedTableEvent) async -> CandidateGameAction {
        
        // 1. Core ML Dense Embedding (384-d)
        guard let vector = await embedderService.embed(text: event.ocrText) else {
            return .rejected(reason: "Failed to generate embedding vector from OCR text.")
        }
        
        // 2. Core ML Card Type Classification
        guard let classification = classifierService.classify(embedding: vector) else {
            return .rejected(reason: "Card type classification failed.")
        }
        
        let predictedType = classification.cardType
        let confidence = classification.confidence
        
        print("🧠 Core ML Predicted Type: [\(predictedType)] (\(String(format: "%.1f", confidence * 100))% confidence)")
        
        // 3. Hybrid Metadata Extraction: Primary (SQLite) -> Fallback (Swift Regex)
        var cardName = "Unindexed Card"
        var energyCost = 0
        var extractedTags = "[]"
        
        // Inside ActionTranslatingEngine.swift (inferAction)

if let dbCard = dbService.fetchCard(by: event.cardID) {
    // Primary Path: Fast SQLite Hit
    cardName = dbCard.cleanName
    energyCost = dbCard.energyCost
    extractedTags = dbCard.extractedTags
} else {
    // Fallback Path: Dynamic SwiftRegexParsingService parsing on raw ocrText
    let parsed = SwiftRegexParsingService.parse(ocrText: event.ocrText)
    extractedTags = parsed.extractedTags
}
        
        // 4. Early Heuristic Filter Logic (Type + Zone Validation)
        switch predictedType {
            
        case "Unit":
            if event.sourceRegion == "Hand" && (event.destinationRegion == "Base" || event.destinationRegion == "Battlefield") {
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
            return .rejected(reason: "Unhandled card type: \(predictedType)")
        }
    }
}
