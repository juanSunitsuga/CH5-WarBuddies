import Testing
@testable import RiftboundTextProcessing

/// The SQLite database keys cards by a hex `card_id`
/// (`69bc5bc6d308c64675ca86bc`) while the vision pipeline keys them by
/// `riftbound_id` (`ogn-007-298`). Those ID spaces don't overlap, so a
/// lookup by `riftbound_id` silently misses every time and the engine
/// falls through to CoreML/regex for cards the database already knows.
/// These tests pin the two keys that *do* work.
@Suite("Card Database Join Keys")
struct CardDatabaseJoinTests {
    private let service = CardDatabaseService()

    @Test("A riftbound_id never joins — this is the mismatch the databaseID field exists to fix")
    func riftboundIDDoesNotJoin() {
        #expect(service.fetchCard(by: "ogn-007-298") == nil)
        #expect(service.fetchCard(by: "ogs-001-024") == nil)
    }

    @Test("The catalogue's hex id is the reliable join key")
    func hexIDJoins() throws {
        let card = try #require(service.fetchCard(by: "69bc5bc6d308c64675ca86bc"))
        #expect(card.cleanName == "Fury Rune")
        #expect(card.cardType == "Rune")
    }

    /// Name matching has to survive the two sources punctuating differently
    /// (`"Annie - Fiery"` vs `"Annie Fiery"`), which is why
    /// `fetchCard(named:)` normalizes rather than comparing raw strings.
    @Test("Name lookup is case- and punctuation-insensitive")
    func nameLookupNormalizes() throws {
        let exact = try #require(service.fetchCard(named: "Fury Rune"))
        #expect(exact.cardID == "69bc5bc6d308c64675ca86bc")

        #expect(service.fetchCard(named: "fury rune")?.cardID == exact.cardID)
        #expect(service.fetchCard(named: "Fury-Rune")?.cardID == exact.cardID)
        #expect(service.fetchCard(named: "  FuryRune  ")?.cardID == exact.cardID)
    }

    @Test("Unknown names and empty input return nil rather than a wrong row")
    func unknownNameReturnsNil() {
        #expect(service.fetchCard(named: "Not A Real Card") == nil)
        #expect(service.fetchCard(named: "") == nil)
        #expect(service.fetchCard(named: "   ") == nil)
    }

    /// The database is the *primary* path — a card it knows must never be
    /// sent to the CoreML classifier, whose type prediction can disagree
    /// (and, for the sample spells, does). Passing `databaseID` is what
    /// routes this to the authoritative answer.
    @Test("A databaseID hit uses the database's card type, not a model guess")
    func databaseIDShortCircuitsTheClassifier() async {
        let engine = ActionTranslatingEngine()
        let event = ObservedTableEvent(
            cardID: "ogn-007-298",                          // riftbound_id — misses on its own
            databaseID: "69bc5bc6d308c64675ca86bc",         // …but this one hits
            ocrText: "",                                     // no text: only the DB can answer
            sourceRegion: "RuneDeck",
            destinationRegion: "RuneArea"
        )

        // "Fury Rune" is a Rune in the database, so this resolves through
        // the Rune branch — reachable only because the DB hit supplied the
        // type without any text to classify.
        guard case .channelRune(_, let name) = await engine.inferAction(event: event) else {
            Issue.record("Expected the database hit to classify this as a Rune")
            return
        }
        #expect(name == "Fury Rune")
    }
}
