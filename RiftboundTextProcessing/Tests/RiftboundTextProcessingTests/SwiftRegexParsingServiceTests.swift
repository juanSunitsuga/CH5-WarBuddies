//
//  SwiftRegexParserTest.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Testing
@testable import RiftboundTextProcessing

@Suite("Swift Regex Parser Tests")
struct SwiftRegexParserTests {

    @Test("Parse action and draw keywords from OCR text")
    func parseActionKeyword() {
        let ocrText = "[Action] Units you play this turn enter ready. Draw 1."
        let result = SwiftRegexParser.parse(ocrText: ocrText)
        
        #expect(result.categories.contains("TAG_ACTION"))
        #expect(result.categories.contains("CMD_DRAW"))
        #expect(result.extractedTags.contains("<TAG_ACTION>[Action]</TAG_ACTION>"))
        #expect(result.extractedTags.contains("<CMD_DRAW>Draw 1</CMD_DRAW>"))
    }

    @Test("Parse combat assault, shield, and stat boost keywords")
    func parseCombatKeywords() {
        let ocrText = "[Assault 2], [Shield 2] (+2 Might while I'm an attacker or defender.)"
        let result = SwiftRegexParser.parse(ocrText: ocrText)
        
        #expect(result.categories.contains("TAG_ASSAULT"))
        #expect(result.categories.contains("TAG_SHIELD"))
        #expect(result.categories.contains("CMD_STAT_BOOST"))
        #expect(result.extractedTags.contains("<TAG_ASSAULT>[Assault 2]</TAG_ASSAULT>"))
    }
    
    @Test("Return empty tags when OCR text contains no rules")
    func parseEmptyMatches() {
        let ocrText = "Simple plain text with no mechanics."
        let result = SwiftRegexParser.parse(ocrText: ocrText)

        #expect(result.extractedTags == "[]")
        #expect(result.categories.isEmpty)
    }

    @Test("Parse Ganking, Accelerate, and Deflect combat keywords")
    func parseExtendedCombatKeywords() {
        let ocrText = "[Ganking] [Accelerate] [Deflect 3]"
        let result = SwiftRegexParser.parse(ocrText: ocrText)

        #expect(result.categories == ["TAG_GANKING", "TAG_ACCELERATE", "TAG_DEFLECT"])
        #expect(result.extractedTags.contains("<TAG_GANKING>[Ganking]</TAG_GANKING>"))
        #expect(result.extractedTags.contains("<TAG_DEFLECT>[Deflect 3]</TAG_DEFLECT>"))
    }

    @Test("CMD_DAMAGE matches a sentence-capitalized \"Deal N\" even without the word damage")
    func parseDamageCommandCaseInsensitive() {
        let ocrText = "[Action] Deal 6 to a unit."
        let result = SwiftRegexParser.parse(ocrText: ocrText)

        #expect(result.categories.contains("CMD_DAMAGE"))
        #expect(result.extractedTags.contains("<CMD_DAMAGE>Deal 6</CMD_DAMAGE>"))
    }

    @Test("Parse ready-unit and conquer commands")
    func parseReadyAndConquerCommands() {
        let ocrText = "Ready another unit. When you conquer, draw 1."
        let result = SwiftRegexParser.parse(ocrText: ocrText)

        #expect(result.categories.contains("CMD_READY"))
        #expect(result.categories.contains("CMD_CONQUER"))
        #expect(result.categories.contains("CMD_DRAW"))
    }

    @Test("Categories always come out in pattern-table order, not text order")
    func categoriesFollowTableOrderRegardlessOfTextOrder() {
        let ocrText = "Draw 1. [Action]"
        let result = SwiftRegexParser.parse(ocrText: ocrText)

        // TAG_ACTION is earlier in the pattern table than CMD_DRAW even
        // though it appears later in the source text.
        #expect(result.categories == ["TAG_ACTION", "CMD_DRAW"])
    }
}
