//
//  File.swift
//  RiftboundTextProcessing
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Foundation
import FoundationModels

/// Structured-output target for the on-device Foundation Model. Kept separate
/// from the `@Model` `RiftboundCard` because `@Generable` and `@Model` don't
/// compose on the same type; `tagCardText` maps this into a `RiftboundCard`.
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct TaggedCardResult: Sendable {
    @Guide(description: "One of: Unit, Spell, Rune, Battlefield, Legend")
    public var cardType: String
    @Guide(description: "The card's energy cost as an integer")
    public var energyCost: Int
    @Guide(description: "Tagged keyword and command strings extracted from the card text")
    public var extractedTags: [String]
    @Guide(description: "Category identifiers for the extracted tags")
    public var categories: [String]
}

@available(iOS 26.0, macOS 26.0, *)
public final class FoundationModelTaggingService: Sendable {
    
    private let session: LanguageModelSession
    
    public init() {
        // Embed rule tagging prompt directly into the on-device session instructions
        let instructions = Instructions(
            """
            SYSTEM PROMPT:
            You are an expert TCG rules parsing engine for "Riftbound". Your task is to analyze card text and extract structured game mechanics, energy costs, card types, and tagged keywords.
            
            STRICT OUTPUT FORMAT:
            You MUST respond ONLY with a valid JSON object matching this schema:
            {
              "cardType": "Unit" | "Spell" | "Rune" | "Battlefield" | "Legend",
              "energyCost": <integer>,
              "extractedTags": ["<TAG>...", "<CMD>..."],
              "categories": ["TAG_ACTION", "TAG_REACTION", "CMD_DRAW", "CMD_STAT_BOOST", ...]
            }
            
            TAGGING RULES MATRIX:
            1. Keywords / Headers:
               - "[Action]" -> "<TAG_ACTION>[Action]</TAG_ACTION>" (Category: "TAG_ACTION")
               - "[Reaction]" -> "<TAG_REACTION>[Reaction]</TAG_REACTION>" (Category: "TAG_REACTION")
               - "[Assault X]" -> "<TAG_ASSAULT>[Assault X]</TAG_ASSAULT>" (Category: "TAG_ASSAULT")
               - "[Shield X]" -> "<TAG_SHIELD>[Shield X]</TAG_SHIELD>" (Category: "TAG_SHIELD")
               - "[Tank]" -> "<TAG_TANK>[Tank]</TAG_TANK>" (Category: "TAG_TANK")
            
            2. Game Commands:
               - "Draw X" -> "<CMD_DRAW>Draw X</CMD_DRAW>" (Category: "CMD_DRAW")
               - "+X Might" -> "<CMD_STAT_BOOST>+X Might</CMD_STAT_BOOST>" (Category: "CMD_STAT_BOOST")
               - "Deal X damage" -> "<CMD_DAMAGE>Deal X damage</CMD_DAMAGE>" (Category: "CMD_DAMAGE")
            
            EXAMPLE INPUT:
            "[Action] Units you play this turn enter ready. Draw 1."
            
            EXAMPLE OUTPUT:
            {
              "cardType": "Spell",
              "energyCost": 0,
              "extractedTags": ["<TAG_ACTION>[Action]</TAG_ACTION>", "<CMD_DRAW>Draw 1</CMD_DRAW>"],
              "categories": ["TAG_ACTION", "CMD_DRAW"]
            }
            """
        )
        
        self.session = LanguageModelSession(instructions: instructions)
    }

    /// Process raw text strictly on-device using Apple Foundation Models
    public func tagCardText(_ text: String) async throws -> RiftboundCard {
        let prompt = Prompt("Analyze and tag the following card text:\n\"\(text)\"")

        // Guided generation forces the model to respond matching the @Generable schema
        let response = try await session.respond(to: prompt, generating: TaggedCardResult.self)
        let result = response.content

        // Map the generated structure into the SwiftData persistence entity
        return RiftboundCard(
            rawText: text,
            cardType: result.cardType,
            energyCost: result.energyCost,
            extractedTags: result.extractedTags,
            categories: result.categories
        )
    }
}
