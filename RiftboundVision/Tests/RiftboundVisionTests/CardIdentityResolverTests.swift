import Testing
import Foundation
import CoreGraphics
@testable import RiftboundVision

/// The one place a detector label becomes a card.
///
/// This logic used to live in `CameraPipelineController`, where the app
/// target has no tests and it could only be verified by reading it. Moving
/// it here is most of why the extraction was worth doing.
@Suite("Card Identity Resolver")
struct CardIdentityResolverTests {

    private static func database() throws -> CardDatabase {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var cardData: URL?
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("RiftboundVisionApp/RiftboundVisionApp/CardData")
            if FileManager.default.fileExists(atPath: candidate.path) { cardData = candidate; break }
            directory = directory.deletingLastPathComponent()
        }
        let found = try #require(cardData)
        let urls = try FileManager.default.contentsOfDirectory(at: found, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try CardDatabase(jsonDeckFiles: urls.map { try Data(contentsOf: $0) })
    }

    private static func legendName(ofDeckContaining fragment: String, in database: CardDatabase) throws -> String {
        let deck = try #require(database.decks.first { $0.name.localizedCaseInsensitiveContains(fragment) })
        let legendID = try #require(deck.legendIDs.first)
        return try #require(database.printing(riftboundID: legendID)?.name)
    }

    private static func track(_ label: String?, committed: Bool = true, id: TrackedObjectID = 1) -> TrackedObject {
        TrackedObject(
            id: id,
            type: .card,
            center: CGPoint(x: 100, y: 100),
            boundingBox: CGRect(x: 60, y: 45, width: 80, height: 110),
            rotation: 0,
            confidence: 0.9,
            isVisible: true,
            lastSeenFrame: 1,
            recognizedLabel: label,
            isIdentityCommitted: committed
        )
    }

    // MARK: - Identity

    @Test("A label resolves to its printing before any deck is known")
    func resolvesBeforeNarrowing() throws {
        let resolver = CardIdentityResolver(database: try Self.database())

        #expect(resolver.printing(forLabel: "Annie Fiery", in: .base)?.name.contains("Annie") == true)
        #expect(resolver.printing(forLabel: nil, in: .base) == nil)
        #expect(resolver.printing(forLabel: "Not A Card At All", in: .base) == nil)
    }

    /// The behaviour the UI depends on: once the deck is known, another
    /// deck's card in your own base is a misread and isn't claimed.
    @Test("Deck scope applies once a Legend has been adopted")
    func scopeAppliesAfterAdoption() throws {
        let database = try Self.database()
        let resolver = CardIdentityResolver(database: database)
        let garenLegend = try Self.legendName(ofDeckContaining: "garen", in: database)

        #expect(resolver.adoptDeckIfLegendSeen(in: [Self.track(garenLegend)]))
        #expect(resolver.hasIdentifiedDeck)

        // An Annie card is not in the Garen deck.
        #expect(resolver.printing(forLabel: "Annie Fiery", in: .base) == nil)
        // Except at a battlefield, where an opponent's cards arrive.
        #expect(resolver.printing(forLabel: "Annie Fiery", in: .battlefield) != nil)
    }

    @Test("Adoption waits for a committed identity")
    func adoptionNeedsCommitment() throws {
        let database = try Self.database()
        let resolver = CardIdentityResolver(database: database)
        let legend = try Self.legendName(ofDeckContaining: "garen", in: database)

        #expect(resolver.adoptDeckIfLegendSeen(in: [Self.track(legend, committed: false)]) == false)
        #expect(resolver.hasIdentifiedDeck == false)
    }

    @Test("A non-Legend never adopts a deck")
    func onlyLegendsAdopt() throws {
        let resolver = CardIdentityResolver(database: try Self.database())

        #expect(resolver.adoptDeckIfLegendSeen(in: [Self.track("Annie Fiery")]) == false)
        #expect(resolver.hasIdentifiedDeck == false)
    }

    @Test("Adopting is reported once, not on every poll that re-sees the Legend")
    func adoptionReportsOnce() throws {
        let database = try Self.database()
        let resolver = CardIdentityResolver(database: database)
        let legend = try Self.legendName(ofDeckContaining: "garen", in: database)

        #expect(resolver.adoptDeckIfLegendSeen(in: [Self.track(legend)]))
        #expect(resolver.adoptDeckIfLegendSeen(in: [Self.track(legend)]) == false)
    }

    @Test("Resetting forgets the deck and stops narrowing")
    func resetStopsNarrowing() throws {
        let database = try Self.database()
        let resolver = CardIdentityResolver(database: database)
        resolver.adoptDeckIfLegendSeen(in: [Self.track(try Self.legendName(ofDeckContaining: "garen", in: database))])

        resolver.resetDeck()

        #expect(resolver.hasIdentifiedDeck == false)
        #expect(resolver.printing(forLabel: "Annie Fiery", in: .base) != nil)
    }

    // MARK: - Kind

    /// Card kind is deliberately *not* deck-scoped: placement rules need to
    /// know a battlefield is a battlefield whoever brought it, and
    /// `.unknown` is permitted everywhere, so scoping would loosen the rules.
    @Test("Kind is unscoped, and cached")
    func kindIsUnscopedAndCached() throws {
        let database = try Self.database()
        let resolver = CardIdentityResolver(database: database)
        resolver.adoptDeckIfLegendSeen(in: [Self.track(try Self.legendName(ofDeckContaining: "garen", in: database))])

        // Out-of-deck, so `printing` refuses it — but its kind is still known.
        #expect(resolver.printing(forLabel: "Annie Fiery", in: .base) == nil)
        #expect(resolver.kind(forLabel: "Annie Fiery") != .unknown)

        // Same answer twice, from the memo the second time.
        #expect(resolver.kind(forLabel: "Annie Fiery") == resolver.kind(forLabel: "Annie Fiery"))
        #expect(resolver.kind(forLabel: "Not A Card") == .unknown)
    }
}
