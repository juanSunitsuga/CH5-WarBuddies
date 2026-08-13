import CoreGraphics
import Foundation

/// The closed set of *physical* events this layer detects. Deliberately
/// does NOT include semantic game actions (PlayCard, DrawCard,
/// ChannelRune, ExhaustCard) — those are what the physical signatures
/// below (a card moving Hand → Board, etc.) mean *according to Riftbound
/// rules*, which is the Expert System's call, not this layer's.
public enum VisionEventType: String, Sendable, Equatable, Codable {
    case objectMoved
    case objectRotated
    case objectAppeared
    case objectDisappeared
}

/// A `VisionEvent` together with whether it survived translation into an
/// `ObservedTableEvent` — the debug tap for the vision layer itself.
///
/// The translated stream is a filtered view: it silently drops events in
/// zones `TableRegion` can't represent (Rune Area, Trash, the decks) and
/// events with no seat to attribute them to. Those are exactly the cases
/// worth seeing when tracking looks broken, so this pairs each event with
/// its fate rather than reporting only the survivors.
public struct VisionEventTrace: Sendable {
    public let event: VisionEvent
    /// `false` when the event never reached the Expert System.
    public let wasForwarded: Bool

    public init(event: VisionEvent, wasForwarded: Bool) {
        self.event = event
        self.wasForwarded = wasForwarded
    }
}

/// The interface between Computer Vision and the Expert System. Produced
/// only after temporal confirmation (`TemporalEventDetector`) — never
/// straight from a single frame's detection.
public struct VisionEvent: Sendable, Equatable {
    public let type: VisionEventType

    public let objectID: TrackedObjectID
    public let objectType: ObjectType

    /// The physical seat this object's owning zone implies, if known.
    /// `nil` for zones with no inherent owner (e.g. still mid-transit,
    /// `.unknown`) — the Expert System adapter should not guess here.
    public let player: Player?

    public let previousZone: Zone?
    public let currentZone: Zone?
    /// Which physical Battlefield card `currentZone` refers to, when
    /// `currentZone == .battlefield` — see `BoardZone.battlefieldSlot`.
    /// `nil` for every other zone.
    public let battlefieldSlot: Int?

    public let previousPosition: CGPoint?
    public let currentPosition: CGPoint?

    public let previousRotation: CGFloat?
    public let currentRotation: CGFloat?

    public let timestamp: TimeInterval
    public let confidence: Float
    /// Carried straight through from `TrackedObject.recognizedLabel` (the
    /// detector's class label, e.g. "Garen - Rugged") when the object that
    /// produced this event has one. Without this, `ExpertSystemAdapter`
    /// had no way to learn *which* `TrackedObjectID` a caller should
    /// `identify(objectID:as:)` — its tracker is private, so nothing
    /// outside the adapter can ever discover the ID to call it with. This
    /// field is what lets the adapter derive `CardIdentification`
    /// automatically instead of depending on an external call that, in
    /// practice, nothing could ever make correctly.
    public let recognizedLabel: String?

    public init(
        type: VisionEventType,
        objectID: TrackedObjectID,
        objectType: ObjectType,
        player: Player?,
        previousZone: Zone?,
        currentZone: Zone?,
        battlefieldSlot: Int? = nil,
        previousPosition: CGPoint?,
        currentPosition: CGPoint?,
        previousRotation: CGFloat?,
        currentRotation: CGFloat?,
        timestamp: TimeInterval,
        confidence: Float,
        recognizedLabel: String? = nil
    ) {
        self.type = type
        self.objectID = objectID
        self.objectType = objectType
        self.player = player
        self.previousZone = previousZone
        self.currentZone = currentZone
        self.battlefieldSlot = battlefieldSlot
        self.previousPosition = previousPosition
        self.currentPosition = currentPosition
        self.previousRotation = previousRotation
        self.currentRotation = currentRotation
        self.timestamp = timestamp
        self.confidence = confidence
        self.recognizedLabel = recognizedLabel
    }
}
