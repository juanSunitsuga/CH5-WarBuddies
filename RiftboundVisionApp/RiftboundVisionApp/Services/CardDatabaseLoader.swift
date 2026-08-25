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
    /// Not a real printing — no `tcgplayer_id`, no official print code, no
    /// card image, because it was never actually published or sold. It
    /// exists purely so `CardDatabase.printing(approximatelyNamed:)`
    /// resolves the YOLO detector's "Token" class label to *something*
    /// other than "unidentified card" in the UI.
    ///
    /// Deliberately minimal: `attributes` (Energy/Might/Power) are left
    /// `nil` rather than guessed, because a spawned unit token's real
    /// stats depend on which ability spawned it (Annie's vs. Garen's),
    /// and `parseAbility` doesn't execute abilities yet (see root
    /// README's Known Gaps) — there's nowhere for source-specific stats
    /// to plug in today. `id`/`riftboundID` deliberately avoid the real
    /// catalogue's `set-number-total` scheme (e.g. `ogn-007-298`) so a
    /// future real printing can never collide with it, and `set.setID`
    /// is `"SYN"` rather than a real set code as a visible marker that
    /// this row isn't from riftcodex.com like everything else here.
    private static let syntheticTokenPrinting = CardPrinting(
        id: "synthetic-token-unit",
        name: "Token",
        riftboundID: "synthetic-token-unit",
        collectorNumber: nil,
        attributes: CardPrinting.Attributes(energy: nil, might: nil, power: nil),
        classification: CardPrinting.Classification(type: "Unit", supertype: "Token", rarity: nil, domain: []),
        text: CardPrinting.CardText(
            plain: "A 1 Might unit card that can only be called by a card's ability.",
            flavour: nil
        ),
        set: CardPrinting.CardSet(setID: "SYN", label: "Synthetic (not a real set)"),
        media: CardPrinting.CardMedia(imageURL: nil),
        orientation: .portrait
    )

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
            return try CardDatabase(jsonDeckFiles: jsonData, synthetic: [syntheticTokenPrinting])
        } catch {
            print("CardDatabaseLoader: failed to parse bundled deck files: \(error)")
            return CardDatabase(deckFiles: [], synthetic: [syntheticTokenPrinting])
        }
    }
}
