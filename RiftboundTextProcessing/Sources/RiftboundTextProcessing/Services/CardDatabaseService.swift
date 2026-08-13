//
//  CardDatabaseService.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 07/08/26.
//

import Foundation
import SQLite3

public final class CardDatabaseService: @unchecked Sendable {
    
    private var db: OpaquePointer?
    
    public init() {
        // Robust resource locator for SPM Bundle.module
        let dbPath = Bundle.module.path(forResource: "RiftboundCardDatabase", ofType: "db")
            ?? Bundle.module.path(forResource: "RiftboundCardDatabase", ofType: "db", inDirectory: "Resources")
            ?? Bundle.module.url(forResource: "RiftboundCardDatabase", withExtension: "db")?.path
        
        if let path = dbPath {
            if sqlite3_open(path, &db) == SQLITE_OK {
                print("✅ Connected to SQLite Card Knowledge Base at: \(path)")
            } else {
                print("❌ Failed to open SQLite DB at path: \(path)")
            }
        } else {
            print("⚠️ RiftboundCardDatabase.db not found in Bundle.module resources.")
        }
    }
    
    public func fetchCard(by cardID: String) -> CardMetadata? {
        guard let db = db else { return nil }
        
        let query = "SELECT card_id, clean_name, card_type, energy_cost, extracted_tags, mechanic_categories FROM cards WHERE card_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (cardID as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let type = String(cString: sqlite3_column_text(statement, 2))
                let energy = Int(sqlite3_column_int(statement, 3))
                let tags = String(cString: sqlite3_column_text(statement, 4))
                let categories = String(cString: sqlite3_column_text(statement, 5))
                
                sqlite3_finalize(statement)
                return CardMetadata(cardID: id, cleanName: name, cardType: type, energyCost: energy, extractedTags: tags, mechanicCategories: categories)
            }
        }
        sqlite3_finalize(statement)
        return nil
    }

    /// Reads every indexed card. Used to seed the SwiftData store on first
    /// launch so the primary SwiftData lookup can resolve ground-truth cards.
    public func fetchAllCards() -> [CardMetadata] {
        guard let db = db else { return [] }

        let query = "SELECT card_id, clean_name, card_type, energy_cost, extracted_tags, mechanic_categories FROM cards;"
        var statement: OpaquePointer?
        var results: [CardMetadata] = []

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(
                    CardMetadata(
                        cardID: Self.text(statement, 0),
                        cleanName: Self.text(statement, 1),
                        cardType: Self.text(statement, 2),
                        energyCost: Int(sqlite3_column_int(statement, 3)),
                        extractedTags: Self.text(statement, 4),
                        mechanicCategories: Self.text(statement, 5)
                    )
                )
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    /// Safely reads a text column, tolerating NULL values.
    private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    // MARK: - Alternate join keys

    /// Name-based lookup. Needed because `card_id` here is the catalogue's
    /// 24-character hex id (`69bc5bc6d308c64675ca86bc`) while the vision
    /// pipeline keys cards by `riftbound_id` (`ogn-007-298`) — those ID
    /// spaces share no values, so a lookup by `riftbound_id` misses every
    /// row. `clean_name` is the only other column the two sides share.
    ///
    /// Matching ignores case and the punctuation/spacing the two sources
    /// disagree on (`"Annie - Fiery"` vs `"Annie Fiery"`), mirroring
    /// `RiftboundVision.CardDatabase.printing(approximatelyNamed:)`.
    public func fetchCard(named name: String) -> CardMetadata? {
        let normalized = Self.normalize(name)
        guard !normalized.isEmpty else { return nil }
        // Normalizing in Swift rather than SQL: SQLite has no portable way
        // to strip arbitrary punctuation, and at 75 rows a scan is free.
        return fetchAllCards().first { Self.normalize($0.cleanName) == normalized }
    }

    /// The bundled printed rules text for a card, if this database has it
    /// (the `plain_text` column). Lets the tagging fallback run for a card
    /// the *caller* couldn't resolve but this database can still describe.
    public func printedText(for cardID: String) -> String? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT plain_text FROM cards WHERE card_id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        // SQLITE_TRANSIENT — sqlite must copy the bytes, since the buffer
        // backing `cardID` can be released before the step runs.
        sqlite3_bind_text(statement, 1, cardID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let value = Self.text(statement, 0)
        return value.isEmpty ? nil : value
    }

    /// Lowercased letters and digits only — drops the spaces, hyphens, and
    /// punctuation the two card sources format differently.
    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public struct CardMetadata {
    public let cardID: String
    public let cleanName: String
    public let cardType: String
    public let energyCost: Int
    public let extractedTags: String
    public let mechanicCategories: String
}
