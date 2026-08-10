import Foundation

/// One card slot in an exported deck: the API returns each unique
/// printing under a numeric string key ("0", "1", ...) — normal art,
/// alternate art, etc. — plus a sibling `"count"` field for how many
/// copies of that card are in the deck. There is no fixed key set to
/// decode against directly, hence the custom `init(from:)` below.
public struct DeckCardEntry: Sendable, Decodable {
    /// Every printing found for this slot, in the order the API listed
    /// them (numeric key order) — `.first` is the card's "primary"
    /// printing for display purposes.
    public let printings: [CardPrinting]
    public let count: Int

    private struct DynamicKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { Int(stringValue) }
        init?(intValue: Int) { self.stringValue = String(intValue) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var indexedPrintings: [(index: Int, printing: CardPrinting)] = []
        var count = 0

        for key in container.allKeys {
            if key.stringValue == "count" {
                count = try container.decode(Int.self, forKey: key)
            } else if let index = key.intValue {
                let printing = try container.decode(CardPrinting.self, forKey: key)
                indexedPrintings.append((index, printing))
            }
        }

        self.printings = indexedPrintings.sorted { $0.index < $1.index }.map(\.printing)
        self.count = count
    }
}

/// One exported deck (e.g. `annie.json`) — see `decode.js` in
/// `~/Documents/ADA/CH5/riftbound` for how these were generated from a
/// deck code via the riftcodex.com API. In practice, the exporter has put
/// every card (including Runes/Battlefields/Legends) into `mainDeck`
/// rather than their nominal sections for these particular files — `
/// CardDatabase` unions all four sections defensively rather than trusting
/// the split.
public struct RiftboundDeckFile: Sendable, Decodable {
    public let name: String
    public let deckCode: String
    public let legend: [DeckCardEntry]
    public let runes: [DeckCardEntry]
    public let battlefields: [DeckCardEntry]
    public let mainDeck: [DeckCardEntry]
}
