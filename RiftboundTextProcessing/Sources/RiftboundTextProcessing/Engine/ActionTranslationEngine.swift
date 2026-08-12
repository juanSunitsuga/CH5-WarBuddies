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

/// Candidate action inferred from an `ObservedTableEvent`, before legality
/// validation by the expert system.
public enum CandidateGameAction: Equatable, Sendable {
    case playUnit(cardID: String, cardName: String, energyCost: Int, targetZone: String, mechanics: String)
    case castSpell(cardID: String, cardName: String, energyCost: Int, mechanics: String)
    case channelRune(cardID: String, cardName: String)
    case rejected(reason: String)
}

public final class ActionTranslatingEngine: @unchecked Sendable {
    
    // Created lazily on the main actor: `SwiftDataCardService` is
    // `@MainActor`-isolated, so it can't be initialized from this class's
    // nonisolated `init()`. Optional `var` defaults to nil without needing
    // main-actor context; `dataService()` builds it once on first use.
    @MainActor private var swiftDataService: SwiftDataCardService?

    public init() {}

    @MainActor
    private func dataService() -> SwiftDataCardService {
        if let existing = swiftDataService { return existing }
        let service = SwiftDataCardService()
        service.seedFromBundledDatabase()
        swiftDataService = service
        return service
    }

    public func inferAction(event: ObservedTableEvent) async -> CandidateGameAction {

        var cardName = "Unindexed Card"
        var cardType = "Unknown"
        var energyCost = 0
        var extractedTags = "[]"

        let swiftDataService = await dataService()

        // 1. PRIMARY PATH: SwiftData Lookup (<0.05ms)
        if let dbCard = await swiftDataService.fetchCard(by: event.cardID) {
            cardName = dbCard.cleanName
            cardType = dbCard.cardType
            energyCost = dbCard.energyCost
            extractedTags = "[\(dbCard.extractedTags.joined(separator: ", "))]"
            print("💾 SwiftData Hit: '\(cardName)' (\(cardType))")
            
        } else if !event.ocrText.isEmpty {
            // 2. FALLBACK PATH: Check runtime availability for Foundation Models
            if #available(iOS 26.0, macOS 26.0, *) {
                print("🤖 Running On-Device Foundation Model Tagging...")
                let foundationService = FoundationModelTaggingService()
                
                do {
                    let taggedCard = try await foundationService.tagCardText(event.ocrText)
                    cardType = taggedCard.cardType
                    energyCost = taggedCard.energyCost
                    extractedTags = "[\(taggedCard.extractedTags.joined(separator: ", "))]"
                    
                    // Cache tagged result into SwiftData for future instant lookups
                    await swiftDataService.saveCard(taggedCard)
                    print("✨ Tagged & Saved via Foundation Model: Type [\(cardType)], Cost [\(energyCost)]")
                } catch {
                    print("⚠️ Foundation Model Error: \(error). Falling back to Regex...")
                    let parsed = SwiftRegexParsingService.parse(ocrText: event.ocrText)
                    extractedTags = parsed.extractedTags
                }
            } else {
                // Older OS / Unsupported Fallback: Fast Swift Regex Parser
                print("⚡ Older OS detected -> Falling back to Swift Regex Parser...")
                let parsed = SwiftRegexParsingService.parse(ocrText: event.ocrText)
                extractedTags = parsed.extractedTags
            }
        }
        
        // 3. Early Heuristic Filter Logic
        switch cardType {
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
                return .rejected(reason: "Spells cannot be placed onto board zones.")
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
