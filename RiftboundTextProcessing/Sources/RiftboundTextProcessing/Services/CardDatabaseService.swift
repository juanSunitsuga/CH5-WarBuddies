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
        textColumn("plain_text", forCardID: cardID)
    }

    /// A short, first-timer-friendly rewrite of a card's rules text (the
    /// `simple_text` column, produced by the data-prep notebook's LangChain
    /// + Gemini pass — see that notebook for why it's a separate column
    /// from `plain_text` rather than a replacement).
    ///
    /// Tries `cardID` first, then `name`. The notebook used to write
    /// `card_id` as `riftbound_id` (`ogn-085-298`) for the rows it
    /// populated, not this database's hex `card_id`
    /// (`69bc5bc6d308c64675ca86bc`) that `RiftboundVision.CardPrinting.id`
    /// — and every other lookup in this file — uses, which meant an
    /// id-only lookup missed every simplified row. A one-time migration
    /// merged each `simple_text` onto its card's correct hex-keyed row and
    /// dropped the wrongly-keyed duplicate, so the id lookup resolves
    /// directly today; the name fallback stays as a defensive path for
    /// whenever the notebook (which still writes `riftbound_id`) gets
    /// re-run and reintroduces the same mismatch.
    public func simplifiedText(for cardID: String, name: String? = nil) -> String? {
        if let byID = textColumn("simple_text", forCardID: cardID), !byID.isEmpty {
            return byID
        }
        guard let name else { return nil }
        return textByName("simple_text", name)
    }

    /// BonBon's hand-curated comment for a card (the `bonbons_comment_changes`
    /// column) — the exact wording from the "Card Description + Comment Fix"
    /// pass, not the algorithmic rewrite `CardPlainLanguage.describeCard`
    /// produces from raw printed text. Callers should prefer this over that
    /// dynamic pass when it resolves, and fall back to the dynamic one
    /// otherwise — the curated wording only covers the cards someone has
    /// actually reviewed so far.
    public func bonbonComment(for cardID: String, name: String? = nil) -> String? {
        if let byID = textColumn("bonbons_comment_changes", forCardID: cardID), !byID.isEmpty {
            return byID
        }
        guard let name else { return nil }
        return textByName("bonbons_comment_changes", name)
    }

    /// Shared `SELECT <column> ... WHERE card_id = ?` — `column` is always
    /// one of this file's own literals, never external input, so string
    /// interpolation here is a column name, not a query parameter (SQLite
    /// can't bind those with `?` anyway).
    private func textColumn(_ column: String, forCardID cardID: String) -> String? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT \(column) FROM cards WHERE card_id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        // SQLITE_TRANSIENT — sqlite must copy the bytes, since the buffer
        // backing `cardID` can be released before the step runs.
        sqlite3_bind_text(statement, 1, cardID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let value = Self.text(statement, 0)
        return value.isEmpty ? nil : value
    }

    /// Full-table scan for `column` by normalized `clean_name` — same idiom
    /// as `fetchCard(named:)`. A separate query rather than routing through
    /// `fetchAllCards()`/`CardMetadata`, which don't carry any of this
    /// table's free-text columns. Still guards against a matching name with
    /// an empty value rather than assuming one row per name — a defensive
    /// leftover from before the `simple_text` migration, cheap to keep in
    /// case a future notebook run reintroduces duplicates.
    private func textByName(_ column: String, _ name: String) -> String? {
        let normalized = Self.normalize(name)
        guard !normalized.isEmpty, let db else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT clean_name, \(column) FROM cards;"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard Self.normalize(Self.text(statement, 0)) == normalized else { continue }
            let value = Self.text(statement, 1)
            if !value.isEmpty { return value }
        }
        return nil
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
