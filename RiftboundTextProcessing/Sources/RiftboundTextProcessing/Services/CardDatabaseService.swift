//
//  CardDatabaseService.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 07/08/26.
//

import Foundation
import SQLite3

public struct CardMetadata {
    public let cardID: String
    public let cleanName: String
    public let cardType: String
    public let energyCost: Int
    public let extractedTags: String
    public let mechanicCategories: String
}

public final class CardDatabaseService {
    
    private var db: OpaquePointer?
    
    public init() {
        // `Bundle.main` is the *host app's* bundle - for a Swift package
        // resource, that's the wrong bundle entirely (it's never where
        // SwiftPM copies this target's resources, whether running via
        // `swift test`, the `RiftboundTextProcessingDemo` executable, or
        // embedded in RiftboundVisionApp). `Bundle.module` is the one
        // SwiftPM generates for this target specifically.
        guard let dbPath = Bundle.module.path(forResource: "RiftboundCardDatabase", ofType: "db") else {
            print("❌ RiftboundCardDatabase.db not found in Bundle.module")
            return
        }
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("✅ Connected to SQLite Card Knowledge Base!")
        }
    }

    /// Queries pre-parsed card metadata directly in Step ② (ActionTranslating.inferAction)
    public func fetchCard(by cardID: String) -> CardMetadata? {
        fetchCard(matching: "card_id = ?", value: cardID)
    }

    /// Name-based lookup, needed because `card_id` in this database is a
    /// 24-character hex hash (`69bc5bc6d308c64675ca86bc`) while the rest of
    /// the pipeline keys cards by their printed `riftbound_id`
    /// (`ogs-001-024`) — the two ID spaces don't overlap at all, so
    /// `fetchCard(by:)` can never hit on an ID that came from the vision
    /// pipeline. `clean_name` is the only column the two sides share, which
    /// makes it the sole usable join key until this database is regenerated
    /// with a `riftbound_id` column.
    ///
    /// Matching is case-insensitive and ignores the punctuation/spacing the
    /// two sources disagree on (`"Annie - Fiery"` vs `"Annie Fiery"`), the
    /// same normalization `RiftboundVision.CardDatabase
    /// .printing(approximatelyNamed:)` performs.
    public func fetchCard(named name: String) -> CardMetadata? {
        let normalized = Self.normalize(name)
        guard !normalized.isEmpty else { return nil }
        // Normalizing in Swift rather than SQL: SQLite has no portable way
        // to strip arbitrary punctuation, and at 75 rows a full scan costs
        // nothing.
        return allCards().first { Self.normalize($0.cleanName) == normalized }
    }

    /// Every row. Small table (tens of cards), read once per lookup — if
    /// this database ever grows past a few hundred rows, replace
    /// `fetchCard(named:)`'s scan with a generated normalized-name column
    /// and an index rather than caching this.
    public func allCards() -> [CardMetadata] {
        guard let db else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT card_id, clean_name, card_type, energy_cost, extracted_tags, mechanic_categories FROM cards;"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }

        var results: [CardMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(metadata(from: statement))
        }
        return results
    }

    private func fetchCard(matching predicate: String, value: String) -> CardMetadata? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT card_id, clean_name, card_type, energy_cost, extracted_tags, mechanic_categories FROM cards WHERE \(predicate) LIMIT 1;"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }

        // SQLITE_TRANSIENT: sqlite must copy the bytes, since the bridged
        // NSString backing them can be released before the step runs.
        sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return metadata(from: statement)
    }

    private func metadata(from statement: OpaquePointer?) -> CardMetadata {
        func column(_ index: Int32) -> String {
            guard let text = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: text)
        }
        return CardMetadata(
            cardID: column(0),
            cleanName: column(1),
            cardType: column(2),
            energyCost: Int(sqlite3_column_int(statement, 3)),
            extractedTags: column(4),
            mechanicCategories: column(5)
        )
    }

    /// Lowercased letters and digits only — drops the spaces, hyphens, and
    /// punctuation the two card sources format differently.
    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
