import Foundation

/// An in-memory index of known card printings, built from one or more
/// exported deck files (`RiftboundDeckFile`). This is intentionally a
/// small, static lookup table, not a live API client — the app decides
/// what data to load it with (bundled JSON, a future full card-pool
/// export, whatever). Card *recognition* (photo → which card) is a
/// separate, not-yet-built concern; this only answers "what do we know
/// about card X once something says it's card X" — see
/// `RecognizedCard`/`ExpertSystemAdapter.identify(objectID:as:)` for the
/// identity side of that seam.
public struct CardDatabase: Sendable {
    public let printingsByRiftboundID: [String: CardPrinting]

    /// - Parameter synthetic: printings that didn't come from a
    ///   `RiftboundDeckFile` export because they were never actually
    ///   printed/sold (e.g. a spawned-unit token proxy) — merged in
    ///   afterward so callers can identify them by name without a real
    ///   card existing in the catalogue for them. Kept as a distinct
    ///   parameter, not mixed into `deckFiles`, so it's always obvious at
    ///   the call site which printings are real riftcodex.com exports and
    ///   which are fabricated stand-ins.
    public init(deckFiles: [RiftboundDeckFile], synthetic: [CardPrinting] = []) {
        var index: [String: CardPrinting] = [:]
        for file in deckFiles {
            let allEntries = file.legend + file.runes + file.battlefields + file.mainDeck
            for entry in allEntries {
                for printing in entry.printings {
                    index[printing.riftboundID] = printing
                }
            }
        }
        for printing in synthetic {
            index[printing.riftboundID] = printing
        }
        self.printingsByRiftboundID = index
    }

    /// Decodes and merges deck files directly from JSON `Data` — the usual
    /// entry point for an app bundling bundled `.json` deck exports.
    public init(jsonDeckFiles: [Data], synthetic: [CardPrinting] = []) throws {
        let decoder = JSONDecoder()
        let files = try jsonDeckFiles.map { try decoder.decode(RiftboundDeckFile.self, from: $0) }
        self.init(deckFiles: files, synthetic: synthetic)
    }

    public func printing(riftboundID: String) -> CardPrinting? {
        printingsByRiftboundID[riftboundID]
    }

    /// Case-insensitive substring match on name — backs a manual "assign
    /// this tracked object to a card" picker, standing in for real
    /// recognition until that exists.
    public func search(_ query: String) -> [CardPrinting] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lowercasedQuery = query.lowercased()
        return printingsByRiftboundID.values
            .filter { $0.name.lowercased().contains(lowercasedQuery) }
            .sorted { $0.name < $1.name }
    }

    public var allPrintings: [CardPrinting] {
        printingsByRiftboundID.values.sorted { $0.name < $1.name }
    }

    /// Looks up a card by name after stripping everything but letters and
    /// digits and lowercasing both sides — e.g. `CoreMLCardDetector`'s
    /// YOLO label "Annie Fiery" and this database's printed name
    /// "Annie - Fiery" both normalize to "anniefiery" and match. A
    /// recognizer's label vocabulary is whatever its training data used
    /// (with or without hyphens/parentheses), which won't necessarily be
    /// byte-for-byte identical to this database's `name` field, so an
    /// exact-string lookup would silently miss real matches.
    public func printing(approximatelyNamed name: String) -> CardPrinting? {
        let target = Self.normalize(name)
        return printingsByRiftboundID.values.first { Self.normalize($0.name) == target }
    }

    private static func normalize(_ string: String) -> String {
        String(string.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
