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
}

public struct CardMetadata {
    public let cardID: String
    public let cleanName: String
    public let cardType: String
    public let energyCost: Int
    public let extractedTags: String
    public let mechanicCategories: String
}
