//
//  File.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Testing
@testable import RiftboundTextProcessing

@Suite("Card Database Service Tests")
struct CardDatabaseServiceTests {

    let dbService = CardDatabaseService()

    @Test("Successfully fetch indexed card from SQLite Bundle.module")
    func fetchIndexedCardSuccess() {
        let cardID = "69bc5bd9d308c64675ca881c" // Garen Rugged
        let card = dbService.fetchCard(by: cardID)
        
        #expect(card != nil)
        #expect(card?.cleanName == "Garen Rugged")
        #expect(card?.cardType == "Unit")
        #expect(card?.energyCost == 6)
        #expect(card?.extractedTags.contains("TAG_ASSAULT") == true)
    }

    @Test("Fetch unindexed card returns nil")
    func fetchUnindexedCardReturnsNil() {
        let cardID = "non_existent_card_9999"
        let card = dbService.fetchCard(by: cardID)
        
        #expect(card == nil)
    }
}
