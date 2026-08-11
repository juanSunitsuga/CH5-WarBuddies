//
//  File.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Testing
@testable import RiftboundActionTranslator

@Suite("Action Translating Engine Integration Tests")
struct ActionTranslatingEngineTests {

    let engine = ActionTranslatingEngine()

    @Test("Infer action for indexed unit card placed to Base")
    func inferActionIndexedUnitToBoard() async {
        let event = ObservedTableEvent(
            cardID: "69bc5bd9d308c64675ca881c", // Garen Rugged
            ocrText: "[Assault 2], [Shield 2] (+2 Might while I'm an attacker or defender.)",
            sourceRegion: "Hand",
            destinationRegion: "Base"
        )
        
        let action = await engine.inferAction(event: event)
        
        switch action {
        case .playUnit(let id, let name, let cost, let zone, let mechanics):
            #expect(id == "69bc5bd9d308c64675ca881c")
            #expect(name == "Garen Rugged")
            #expect(cost == 6)
            #expect(zone == "Base")
            #expect(mechanics.contains("TAG_ASSAULT"))
        default:
            Issue.record("Expected .playUnit action for indexed unit card.")
        }
    }

    @Test("Infer action for unindexed spell using dynamic Swift Regex fallback")
    func inferActionUnindexedSpellRegexFallback() async {
        let event = ObservedTableEvent(
            cardID: "unindexed_spell_999",
            ocrText: "[Action] Units you play this turn enter ready. Draw 1.",
            sourceRegion: "Hand",
            destinationRegion: "Trash"
        )
        
        let action = await engine.inferAction(event: event)
        
        switch action {
        case .castSpell(let id, let name, _, let mechanics):
            #expect(id == "unindexed_spell_999")
            #expect(name == "Unindexed Card")
            #expect(mechanics.contains("TAG_ACTION"))
            #expect(mechanics.contains("CMD_DRAW"))
        default:
            Issue.record("Expected .castSpell action with regex fallback mechanics.")
        }
    }

    @Test("Early filter rejects playing spells directly onto Battlefield")
    func inferActionRejectsInvalidSpellPlacement() async {
        let event = ObservedTableEvent(
            cardID: "unindexed_spell_888",
            ocrText: "[Action] Units you play this turn enter ready. Draw 1.",
            sourceRegion: "Hand",
            destinationRegion: "Battlefield" // Spells cannot sit on Battlefield
        )
        
        let action = await engine.inferAction(event: event)
        
        switch action {
        case .rejected(let reason):
            #expect(reason.contains("Spells cannot be placed onto board zones"))
        default:
            Issue.record("Early filter should reject playing spells directly onto Battlefield.")
        }
    }
}
