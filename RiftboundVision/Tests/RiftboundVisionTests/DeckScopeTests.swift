import Testing
import Foundation
@testable import RiftboundVision

/// Narrowing identification to the deck actually on the table.
///
/// The rosters here are the real bundled exports, so "a Garen deck rejects
/// an Annie card" is a statement about the cards this app ships, not about
/// a fixture built to make the rule look good.
@Suite("Deck Scope")
struct DeckScopeTests {

    /// The app's own deck exports. Falls back to the test fixture when the
    /// app bundle's copies aren't reachable from the package's test run.
    private static func database() throws -> CardDatabase {
        // Walk up from this file rather than counting directory levels —
        // the count was wrong once already, and a search says what it is
        // actually looking for.
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var cardData: URL?
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("RiftboundVisionApp/RiftboundVisionApp/CardData")
            if FileManager.default.fileExists(atPath: candidate.path) { cardData = candidate; break }
            directory = directory.deletingLastPathComponent()
        }

        let found = try #require(cardData, "couldn't find the app's CardData directory above \(#filePath)")
        let urls = (try? FileManager.default.contentsOfDirectory(at: found, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        try #require(!urls.isEmpty, "no deck exports in \(found.path)")
        return try CardDatabase(jsonDeckFiles: urls.map { try Data(contentsOf: $0) })
    }

    private static func roster(named fragment: String, in database: CardDatabase) throws -> DeckRoster {
        try #require(
            database.decks.first { $0.name.localizedCaseInsensitiveContains(fragment) },
            "no deck whose name contains '\(fragment)' — found \(database.decks.map(\.name))"
        )
    }

    @Test("Each bundled deck keeps its own roster, with a legend")
    func rostersSurviveTheFlatIndex() throws {
        let database = try Self.database()

        #expect(database.decks.count >= 2)
        for deck in database.decks {
            #expect(!deck.legendIDs.isEmpty, "\(deck.name) has no legend")
            #expect(!deck.memberIDs.isEmpty)
        }
    }

    /// The headline behaviour: play Garen, and an Annie card in your own
    /// base is a misread rather than a card.
    @Test("A Garen deck stops believing Annie cards outside the battlefield")
    func outOfDeckCardsAreRejected() throws {
        let database = try Self.database()
        let garen = try Self.roster(named: "garen", in: database)
        let annie = try Self.roster(named: "annie", in: database)

        var scope = DeckScope(rosters: database.decks)
        let garenLegend = try #require(garen.legendIDs.first)
        scope.identifyDeck(fromLegend: garenLegend)
        #expect(scope.activeDeckName == garen.name)

        // An Annie card that Garen's deck doesn't contain.
        let annieOnly = try #require(annie.memberIDs.subtracting(garen.memberIDs).sorted().first)

        #expect(scope.allows(annieOnly, in: .base) == false)
        #expect(scope.allows(annieOnly, in: .player1Hand) == false)
        #expect(scope.allows(annieOnly, in: .runeArea) == false)

        // Garen's own cards are still fine everywhere.
        let garenOwn = try #require(garen.memberIDs.subtracting(annie.memberIDs).sorted().first)
        #expect(scope.allows(garenOwn, in: .base))
    }

    /// The exception that makes the rule usable: an opponent's card really
    /// does arrive at a battlefield, and the engine can't track combat
    /// against a card it refuses to name.
    @Test("An out-of-deck card at a battlefield is still identified")
    func battlefieldIsAlwaysInScope() throws {
        let database = try Self.database()
        let garen = try Self.roster(named: "garen", in: database)
        let annie = try Self.roster(named: "annie", in: database)

        var scope = DeckScope(rosters: database.decks)
        scope.identifyDeck(fromLegend: try #require(garen.legendIDs.first))

        let annieOnly = try #require(annie.memberIDs.subtracting(garen.memberIDs).sorted().first)
        #expect(scope.allows(annieOnly, in: .battlefield))
    }

    /// Narrowing before the deck is known would hide the very Legend that
    /// identifies it.
    @Test("Nothing is narrowed until a legend has been seen")
    func noNarrowingBeforeIdentification() throws {
        let database = try Self.database()
        let annie = try Self.roster(named: "annie", in: database)
        let scope = DeckScope(rosters: database.decks)

        #expect(scope.hasIdentifiedDeck == false)
        #expect(scope.allows(try #require(annie.memberIDs.sorted().first), in: .base))
    }

    @Test("A label belonging to no deck never identifies one")
    func unknownLegendIsIgnored() throws {
        var scope = DeckScope(rosters: try Self.database().decks)

        #expect(scope.identifyDeck(fromLegend: "not-a-real-card") == false)
        #expect(scope.hasIdentifiedDeck == false)
    }

    @Test("Resetting forgets the deck, for a new match")
    func resetClearsIt() throws {
        let database = try Self.database()
        var scope = DeckScope(rosters: database.decks)
        scope.identifyDeck(fromLegend: try #require(Self.roster(named: "garen", in: database).legendIDs.first))
        #expect(scope.hasIdentifiedDeck)

        scope.reset()
        #expect(scope.hasIdentifiedDeck == false)
    }
}
