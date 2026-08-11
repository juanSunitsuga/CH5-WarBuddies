//
//  SwiftRegexParserTest.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Testing
@testable import RiftboundActionTranslator

@Suite("Swift Regex Parser Tests")
struct SwiftRegexParsingServiceTests {

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
}
