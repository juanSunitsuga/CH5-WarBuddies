import Foundation
import RiftboundTextProcessing

struct MainApp {
    
    static func main() async {
        print("🚀 Initializing Action Translating Engine (Step ②)...\n")
        
        let engine = ActionTranslatingEngine()
        
        // Test Events (Including indexed cards + unindexed OCR reads)
        let testEvents = [
            ObservedTableEvent(
                cardID: "69bc5bd9d308c64675ca881c", // Garen Rugged (Indexed in SQLite)
                ocrText: "[Assault 2], [Shield 2] (+2 Might while I'm an attacker or defender.)",
                sourceRegion: "Hand",
                destinationRegion: "Base"
            ),
            ObservedTableEvent(
                cardID: "unindexed_ocr_card_999", // Unindexed Card (Triggers Swift Regex Fallback!)
                ocrText: "[Action] Units you play this turn enter ready. Draw 1.",
                sourceRegion: "Hand",
                destinationRegion: "Battlefield"
            )
        ]
        
        for (idx, event) in testEvents.enumerated() {
            print("==================================================")
            print("📌 Event [\(idx + 1)]: Event for Card [\(event.cardID)]")
            
            let candidateAction = await engine.inferAction(event: event)
            
            switch candidateAction {
            case .playUnit(let id, let name, let cost, let zone, let mechanics):
                print("✅ Proposed Action: .playUnit(name: \"\(name)\" [\(id)], cost: \(cost), zone: '\(zone)', mechanics: \(mechanics))")
            case .castSpell(let id, let name, let cost, let mechanics):
                print("✅ Proposed Action: .castSpell(name: \"\(name)\" [\(id)], cost: \(cost), mechanics: \(mechanics))")
            case .channelRune(let id, let name):
                print("✅ Proposed Action: .channelRune(name: \"\(name)\" [\(id)])")
            case .rejected(let reason):
                print("🚫 Rejected by Early Filter: \(reason)")
            }
            print("==================================================\n")
        }
        
        print("✅ Pipeline Execution Finished!")
    }
}

await MainApp.main()
