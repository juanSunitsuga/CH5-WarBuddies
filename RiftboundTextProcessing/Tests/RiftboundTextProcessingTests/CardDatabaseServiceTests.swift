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

    /// The data-prep notebook used to write its `simple_text` rows keyed
    /// by `riftbound_id` (`ogn-085-298`) rather than this database's hex
    /// `card_id` — a data bug fixed by a one-time migration that merged
    /// `simple_text` onto the correct hex-keyed row and dropped the
    /// duplicate (see the migration note in `CardDatabaseService.swift`).
    /// This is the happy path that migration exists for: the id every
    /// other lookup in this file already uses now resolves `simple_text`
    /// directly, no name fallback needed.
    @Test("simplifiedText finds a card by its hex id directly")
    func simplifiedTextResolvesByHexID() {
        let hexID = "69bc5bcbd308c64675ca8714" // Falling Comet
        let result = dbService.simplifiedText(for: hexID)

        #expect(result != nil)
        // The rewrite should read as a sentence, not carry over the raw
        // rules text's own bracketed keyword or reminder-text parenthetical.
        #expect(result?.contains("[Action]") == false)
    }

    /// The name fallback stays in place defensively — if a future notebook
    /// run reintroduces a wrongly-keyed row (or any other id mismatch),
    /// this is what keeps `simplifiedText` resolving anyway. Forced here by
    /// deliberately passing an id that can't match, so the fallback path
    /// itself stays covered even though the data no longer requires it.
    @Test("simplifiedText falls back to a name match when the id doesn't resolve")
    func simplifiedTextFallsBackToName() {
        let result = dbService.simplifiedText(for: "not-the-real-id", name: "Falling Comet")

        #expect(result != nil)
        #expect(result?.contains("[Action]") == false)
    }

    @Test("simplifiedText returns nil rather than a stale id when neither key matches")
    func simplifiedTextReturnsNilWhenUnresolved() {
        let result = dbService.simplifiedText(for: "not-a-real-id", name: "Not A Real Card")
        #expect(result == nil)
    }

    /// Same "Card Description + Comment Fix" pass, but this column is read
    /// live at runtime (`MascotInstructionPanel`'s BonBon comment) rather
    /// than just being descriptive text — so this checks the exact same
    /// resolution path as `simplifiedText`, not just that the column exists.
    @Test("bonbonComment finds a card's curated comment by its hex id")
    func bonbonCommentResolvesByHexID() {
        let hexID = "69bc5bd2d308c64675ca879e" // Daring Poro
        let result = dbService.bonbonComment(for: hexID)

        #expect(result == "To play it, exhaust 2 runes. When it attacks, it gets +1 Might.")
    }

    @Test("bonbonComment falls back to a name match when the id doesn't resolve")
    func bonbonCommentFallsBackToName() {
        let result = dbService.bonbonComment(for: "not-the-real-id", name: "Daring Poro")
        #expect(result == "To play it, exhaust 2 runes. When it attacks, it gets +1 Might.")
    }

    @Test("bonbonComment returns nil rather than a stale id when neither key matches")
    func bonbonCommentReturnsNilWhenUnresolved() {
        let result = dbService.bonbonComment(for: "not-a-real-id", name: "Not A Real Card")
        #expect(result == nil)
    }

    /// A card the fix pass has blanked out (a Rune, or any other card with
    /// no printed ability) stores an empty column value, not the sheet's
    /// "leave it blank" instruction text — the caller reads this as "no
    /// curated comment yet" the same as a card the pass hasn't reached.
    @Test("bonbonComment returns nil for a card the fix pass left blank on purpose")
    func bonbonCommentNilForIntentionallyBlankCard() {
        let hexID = "69bc5bcbd308c64675ca8718" // Mind Rune
        let result = dbService.bonbonComment(for: hexID)

        #expect(result == nil)
    }
}
