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

    private let container: ModelContainer?
    private let context: ModelContext?

    /// This package's own store file.
    ///
    /// A `ModelConfiguration` without an explicit URL uses the process-wide
    /// default (`Application Support/default.store`) — which the *host app*
    /// is already using for its own, completely different schema. Two
    /// containers backing one file with mismatched models makes the store
    /// unopenable, and SwiftData then throws from inside a fault, far from
    /// the cause: `NSCocoaErrorDomain 256, "default.store couldn't be
    /// opened"` raised in the app's own board-state code. Owning a
    /// separate file keeps the two schemas from colliding at all.
    private static var storeURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let directory = base.appendingPathComponent("RiftboundTextProcessing", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("CardTags.store")
    }

    public init() {
        let schema = Schema([RiftboundCard.self])
        let configuration: ModelConfiguration = Self.storeURL.map {
            ModelConfiguration(schema: schema, url: $0)
        } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        // Deliberately not `fatalError`: this store is a cache in front of
        // the bundled SQLite database, which remains the source of truth.
        // An unwritable or incompatible store should cost cached tags, not
        // take the whole app down at launch.
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            self.container = container
            self.context = ModelContext(container)
        } else {
            print("⚠️ SwiftData card cache unavailable — falling back to the bundled SQLite database only.")
            self.container = nil
            self.context = nil
        }
    }
    
    /// Lookup card by ID in SwiftData. `nil` both when the card isn't
    /// cached and when there's no usable store — callers fall back to the
    /// bundled SQLite database either way.
    public func fetchCard(by cardID: String) -> RiftboundCard? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<RiftboundCard>(
            predicate: #Predicate { $0.cardID == cardID }
        )
        return try? context.fetch(descriptor).first
    }

    /// Insert or update a card tagged by the Foundation Model into SwiftData
    public func saveCard(_ card: RiftboundCard) {
        guard let context else { return }
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
        guard let context else { return }
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
