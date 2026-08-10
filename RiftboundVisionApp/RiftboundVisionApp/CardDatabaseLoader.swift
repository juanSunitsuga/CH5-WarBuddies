import Foundation
import RiftboundVision

/// Loads the 4 bundled proving-ground deck exports
/// (`~/Documents/ADA/CH5/riftbound/{annie,lux,garen,master_yi}.json`,
/// copied into this target's `CardData/` folder) into a `CardDatabase` at
/// launch. This is sample data, not the full card pool — anything not in
/// one of these 4 beginner decks won't resolve. Swap in a fuller export
/// here once one exists; nothing else in the app needs to change, since
/// everything downstream only depends on `CardDatabase`'s API.
enum CardDatabaseLoader {
    static func loadBundled() -> CardDatabase {
        let deckNames = ["annie", "lux", "garen", "master_yi"]
        let jsonData: [Data] = deckNames.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                print("CardDatabaseLoader: missing bundled resource \(name).json")
                return nil
            }
            do {
                return try Data(contentsOf: url)
            } catch {
                print("CardDatabaseLoader: couldn't read \(name).json: \(error)")
                return nil
            }
        }

        do {
            return try CardDatabase(jsonDeckFiles: jsonData)
        } catch {
            print("CardDatabaseLoader: failed to parse bundled deck files: \(error)")
            return CardDatabase(deckFiles: [])
        }
    }
}
