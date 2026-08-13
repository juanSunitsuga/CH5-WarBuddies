//
//  File.swift
//  RiftboundVisionApp
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Foundation
import RiftboundTextProcessing // 👈 Native SPM local package

/// High-level orchestration pipeline connecting Vision board events with SQLite & ML
public final class CardIntegrationPipeline: ObservableObject {
    
    private let dbService = CardDatabaseService()
    private let regexService = SwiftRegexParsingService()
    private let actionEngine = ActionTranslatingEngine()
    
    public init() {}
    
    /// 1. Fetch clean, pre-tagged card details instantly from SQLite (<0.05ms)
    public func fetchCardDetails(cardID: String) -> CardMetadata? {
        if let card = dbService.fetchCard(by: cardID) {
            print("💾 SQLite DB Hit: Loaded '\(card.cleanName)' (\(card.cardType))")
            print("🏷️ Pre-Parsed Mechanics: \(card.extractedTags)")
            return card
        }
        print("⚠️ Card ID [\(cardID)] not found in SQLite DB.")
        return nil
    }
    
    /// 2. Translate board moves into candidate GameActions (No OCR needed!)
    public func translateBoardMove(
        cardID: String,
        ocrText: String = "",
        sourceRegion: String,
        destinationRegion: String
    ) async -> CandidateGameAction {
        
        let event = ObservedTableEvent(
            cardID: cardID,
            ocrText: ocrText,
            sourceRegion: sourceRegion,
            destinationRegion: destinationRegion
        )
        
        return await actionEngine.inferAction(event: event)
    }
    
    /// 3. Dynamic Word Tagging fallback for raw rule texts
    public func tagRawText(_ text: String) -> ParsedOCRMechanics {
        return SwiftRegexParsingService.parse(ocrText: text)
    }
}
