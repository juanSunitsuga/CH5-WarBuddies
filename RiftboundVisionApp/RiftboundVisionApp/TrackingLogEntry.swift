import Foundation
import RiftboundVision

/// One raw vision-layer event, rendered for the on-screen tracking log.
///
/// Deliberately built from `VisionEvent`, not from the translated
/// `ObservedTableEvent`: the translated stream drops every zone
/// `TableRegion` can't express (Rune Area, Trash, Main/Rune Deck, Legend,
/// Champion) and everything without a seat, which is precisely what you
/// need to see when tracking looks wrong. Debugging tracking through the
/// translated stream means debugging through a filter that hides the
/// interesting cases.
struct TrackingLogEntry: Identifiable {
    /// The three things worth seeing while debugging tracking: a card
    /// arriving, a card changing zone, and a card being turned.
    ///
    /// `.objectDisappeared` deliberately has no case. A track ending is a
    /// statement about the *camera* — occlusion, a hand in the way, a
    /// dropped frame — not about the player, and it fired constantly enough
    /// to bury the three events that do matter.
    enum Kind {
        case appeared
        case moved
        /// Rule 592–593: turned sideways is Exhaust, turned back is Ready.
        case turned
    }

    let id = UUID()
    let kind: Kind
    /// Tracker identity. The key signal in this log: a card that keeps
    /// getting a *new* number each time it's touched is being re-created
    /// rather than followed, which is what stops a play being recognized.
    let trackID: Int
    let card: String
    /// Zone transition, or the single zone for non-move events.
    let transition: String
    let confidence: Float
    /// `false` when the event never reached the Expert System — normally
    /// because its zone has no `TableRegion` representation.
    let wasForwarded: Bool
    let timestamp: Date

    /// `nil` for events this log doesn't show — currently only a track
    /// ending. Filtering here rather than at the call site keeps the rule
    /// next to the enum that states it.
    init?(trace: VisionEventTrace) {
        let event = trace.event
        switch event.type {
        case .objectAppeared: kind = .appeared
        case .objectMoved: kind = .moved
        case .objectRotated: kind = .turned
        case .objectDisappeared: return nil
        }

        trackID = event.objectID
        card = event.recognizedLabel ?? "unrecognized"
        confidence = event.confidence
        wasForwarded = trace.wasForwarded
        timestamp = Date()

        let from = event.previousZone.map(Self.name) ?? "—"
        let to = event.currentZone.map(Self.name) ?? "—"
        switch event.type {
        case .objectMoved:
            transition = "\(from) → \(to)"
        case .objectAppeared:
            transition = "appeared in \(to)"
        case .objectRotated:
            // 592/593: a 90° turn is Exhaust, back to 0° is Ready.
            let exhausted = event.currentRotation.map { abs($0.truncatingRemainder(dividingBy: .pi)) > 0.01 } ?? false
            transition = "\(exhausted ? "EXHAUSTED" : "readied") in \(to)"
        case .objectDisappeared:
            transition = ""   // unreachable — filtered out above
        }
    }

    /// Battlefield rows carry their slot, since a mat can have more than
    /// one and "battlefield" alone wouldn't say which.
    private static func name(_ zone: Zone) -> String {
        switch zone {
        case .player1Hand, .player2Hand: return "Hand"
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case .runeArea: return "Rune Area"
        case .runeDeck: return "Rune Deck"
        case .mainDeck: return "Main Deck"
        case .trash: return "Trash"
        case .legend: return "Legend"
        case .champion: return "Champion"
        case .unknown: return "off-mat"
        }
    }
}
