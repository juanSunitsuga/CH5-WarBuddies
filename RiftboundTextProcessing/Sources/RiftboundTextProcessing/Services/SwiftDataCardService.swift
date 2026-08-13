//
//  File.swift
//  RiftboundTextProcessing
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Foundation
import SwiftData

@MainActor
public final class SwiftDataCardService {
    
    private let container: ModelContainer
    private let context: ModelContext
    
    public init() {
        do {
            let schema = Schema([RiftboundCard.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.container = try ModelContainer(for: schema, configurations: [config])
            self.context = ModelContext(container)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }
    
    /// Lookup card by ID in SwiftData
    public func fetchCard(by cardID: String) -> RiftboundCard? {
        let descriptor = FetchDescriptor<RiftboundCard>(
            predicate: #Predicate { $0.cardID == cardID }
        )
        return try? context.fetch(descriptor).first
    }
    
    /// Insert or update a card tagged by the Foundation Model into SwiftData
    public func saveCard(_ card: RiftboundCard) {
        context.insert(card)
        try? context.save()
    }

    /// Imports the bundled SQLite card database into SwiftData. Indexed
    /// (ground-truth) cards ship in SQLite; this makes them present in the
    /// primary SwiftData store so `fetchCard(by:)` can resolve them.
    ///
    /// Idempotent per card: only cards whose `cardID` is absent are inserted,
    /// so it's safe to call on every launch and isn't defeated by unrelated
    /// Foundation-Model-cached entries already in the store.
    public func seedFromBundledDatabase() {
        let cards = CardDatabaseService().fetchAllCards()
        guard !cards.isEmpty else { return }

        var inserted = 0
        for meta in cards {
            let cardID = meta.cardID
            var descriptor = FetchDescriptor<RiftboundCard>(
                predicate: #Predicate { $0.cardID == cardID }
            )
            descriptor.fetchLimit = 1
            if (try? context.fetch(descriptor))?.isEmpty == false { continue }

            context.insert(
                RiftboundCard(
                    cardID: meta.cardID,
                    cleanName: meta.cleanName,
                    rawText: "",
                    cardType: meta.cardType,
                    energyCost: meta.energyCost,
                    extractedTags: Self.splitList(meta.extractedTags, stripBrackets: true),
                    categories: Self.splitList(meta.mechanicCategories, stripBrackets: false)
                )
            )
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
            print("🌱 Seeded SwiftData with \(inserted) cards from bundled SQLite DB.")
        }
    }

    /// Parses the SQLite string encodings into arrays. `extracted_tags` is
    /// wrapped in `[...]` and `, `-joined; `mechanic_categories` is just
    /// `, `-joined.
    private static func splitList(_ raw: String, stripBrackets: Bool) -> [String] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripBrackets {
            if value.hasPrefix("[") { value.removeFirst() }
            if value.hasSuffix("]") { value.removeLast() }
        }
        return value
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
