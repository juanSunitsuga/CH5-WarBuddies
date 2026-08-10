import Testing
import Foundation
@testable import RiftboundVision

/// Fixture is a trimmed real slice of `~/Documents/ADA/CH5/riftbound/annie.json`
/// (5 card slots, unmodified field values) — verifies parsing against the
/// actual riftcodex.com API shape, not a hand-rolled approximation of it.
struct CardDatabaseTests {

    private func loadFixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "annie_trimmed", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test("A deck file with print-variant-wrapped slots decodes into flat CardPrinting entries")
    func decodesDeckFile() throws {
        let data = try loadFixture()
        let database = try CardDatabase(jsonDeckFiles: [data])

        // Fury Rune has 2 printings (normal + alternate art), each with
        // its own riftbound_id, both should be indexed.
        #expect(database.printing(riftboundID: "ogn-007-298")?.name == "Fury Rune")
        #expect(database.printing(riftboundID: "ogn-007a-298")?.name == "Fury Rune (Alternate Art)")
    }

    @Test("Card attributes (energy/might/power) decode correctly for a Unit")
    func decodesUnitAttributes() throws {
        let data = try loadFixture()
        let database = try CardDatabase(jsonDeckFiles: [data])

        let mysticPoro = try #require(database.allPrintings.first { $0.name == "Mystic Poro" })
        #expect(mysticPoro.attributes.energy == 2)
        #expect(mysticPoro.attributes.might == 2)
        #expect(mysticPoro.classification.type == "Unit")
    }

    @Test("search() matches by case-insensitive substring")
    func searchMatchesCaseInsensitiveSubstring() throws {
        let data = try loadFixture()
        let database = try CardDatabase(jsonDeckFiles: [data])

        let results = database.search("annie")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.lowercased().contains("annie") })
    }

    @Test("search() with an empty query returns nothing")
    func emptySearchReturnsNothing() throws {
        let data = try loadFixture()
        let database = try CardDatabase(jsonDeckFiles: [data])

        #expect(database.search("").isEmpty)
    }
}
