import Foundation
import CoreGraphics

/// The printed shape of the card — "portrait" for everything that isn't a
/// Battlefield, "landscape" for Battlefields (confirmed against the
/// bundled deck data: every non-Battlefield type observed is portrait).
/// This is what makes `isExhausted(observedBoundingBox:)` possible without
/// a true rotation-angle signal — see its doc comment.
public enum CardOrientation: String, Sendable, Decodable, Equatable {
    case portrait
    case landscape
}

/// One printed version of a Riftbound card — matches the shape returned by
/// the riftcodex.com card API (see `decode.js` in the deck-export tooling
/// this schema was transcribed from). "Printing" because a single card can
/// have multiple entries here (normal art, alternate art, etc.), each with
/// its own `riftboundID`.
public struct CardPrinting: Sendable, Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let riftboundID: String
    public let collectorNumber: Int?
    public let attributes: Attributes
    public let classification: Classification
    public let text: CardText
    public let set: CardSet
    public let media: CardMedia
    public let orientation: CardOrientation

    public struct Attributes: Sendable, Decodable, Equatable {
        /// Rule 130.2: printed Energy cost.
        public let energy: Int?
        /// Rule 139.2: printed Might (Units only).
        public let might: Int?
        /// Rule 130.3: printed Power symbol count.
        public let power: Int?
    }

    public struct Classification: Sendable, Decodable, Equatable {
        /// e.g. "Unit", "Spell", "Rune", "Battlefield", "Legend", "Gear".
        public let type: String
        public let supertype: String?
        public let rarity: String?
        public let domain: [String]
    }

    public struct CardText: Sendable, Decodable, Equatable {
        public let plain: String
        public let flavour: String?
    }

    public struct CardSet: Sendable, Decodable, Equatable {
        public let setID: String
        public let label: String

        enum CodingKeys: String, CodingKey {
            case setID = "set_id"
            case label
        }
    }

    public struct CardMedia: Sendable, Decodable, Equatable {
        public let imageURL: URL?

        enum CodingKeys: String, CodingKey {
            case imageURL = "image_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, attributes, classification, text, set, media, orientation
        case riftboundID = "riftbound_id"
        case collectorNumber = "collector_number"
    }
}

extension CardPrinting {
    /// Rule 592/593: an Exhausted card is rotated 90° from its printed
    /// orientation. `CoreMLCardDetector` only gives axis-aligned boxes (no
    /// true rotation angle — see its doc comment), but that's actually
    /// enough once the card is identified: compare the *observed* box's
    /// long axis against this card's *printed* orientation. A portrait
    /// card observed as a wide box (or a landscape card observed as a
    /// tall box) has been rotated 90° — Exhausted. Matching axes means
    /// Ready.
    public func isExhausted(observedBoundingBox box: CGRect) -> Bool {
        let observedIsTall = box.height > box.width
        let printedIsPortrait = orientation == .portrait
        return observedIsTall != printedIsPortrait
    }
}
