import CoreGraphics

/// What kind of physical object this is — deliberately coarse. The tracker
/// answers "which physical object is this," not "what card is this"; exact
/// card identity is a separate concern (see `Recognition/RecognizedCard.swift`)
/// that maps onto a `TrackedObject.id` after the fact, once a
/// card-recognition system exists.
public enum ObjectType: String, Sendable, Equatable, Codable {
    case card
    case rune
    case unknown
}

/// A stable identifier for one physical object as tracked across frames.
/// NOT the same as a Riftbound card identity — `ExpertSystemAdapter` is
/// responsible for mapping this to an `ObjectID`/`CardDefID` once the
/// object has been (re-)identified by card recognition.
public typealias TrackedObjectID = Int

/// One physical object's current tracked state. This is deliberately a
/// plain value type with no game semantics attached — no legality, no
/// "this represents a Standard Move," nothing. `TemporalEventDetector` is
/// the layer that turns a sequence of these into a `VisionEvent`.
public struct TrackedObject: Sendable, Equatable {
    public let id: TrackedObjectID
    public var type: ObjectType

    public var center: CGPoint
    public var boundingBox: CGRect
    /// Radians, arbitrary reference frame — callers normalize as needed.
    public var rotation: CGFloat

    public var previousZone: Zone
    public var currentZone: Zone

    /// Position delta per second, in the same coordinate space as `center`.
    public var velocity: CGVector

    public var confidence: Float
    public var isVisible: Bool

    public var lastSeenFrame: Int

    /// Stacking order when this object overlaps others: higher sits on top.
    /// A Unit with an Equipment/Rune tucked beneath it gets the higher
    /// `zIndex`; the piece underneath keeps a lower one. Populated by
    /// `UnderlayResolver`, not the tracker — the tracker only knows
    /// geometry, and z-order depends on card *roles* it can't see.
    public var zIndex: Int
    /// IDs of objects physically underlaid beneath this one (an Equipment
    /// or Rune under a Unit). Also populated by `UnderlayResolver`. Empty
    /// for a lone card. See `underlaidCardIDs`'s role in surviving
    /// occlusion: an underlaid piece keeps its identity here even once the
    /// top card hides its bounding box from the detector.
    public var underlaidCardIDs: [TrackedObjectID]

    /// Ready (upright) vs Exhausted (tapped), inferred purely from the
    /// current bounding box — see `CGRect.cardStance`. Cheap and robust
    /// across the bbox re-initialization that happens when a card rotates,
    /// unlike `rotation`. This is the identity-free fallback: once a card
    /// *is* recognized, `CardPrinting.isExhausted(observedBoundingBox:)` is
    /// the better answer, since it knows whether the card is printed
    /// portrait or landscape.
    public var stance: CardStance { boundingBox.cardStance }

    /// The class label a recognizer attached to the detection that last
    /// matched this track, if any (e.g. `CoreMLCardDetector`'s YOLO class
    /// name — "Annie Fiery"). `nil` for detectors that don't do identity
    /// (e.g. `VisionRectangleDetector`). This is a raw label, not a
    /// resolved `CardPrinting` — matching it against a `CardDatabase` is
    /// the caller's job, same seam `RecognizedCard`/`identify(objectID:as:)`
    /// already describes.
    public var recognizedLabel: String?

    public init(
        id: TrackedObjectID,
        type: ObjectType,
        center: CGPoint,
        boundingBox: CGRect,
        rotation: CGFloat,
        previousZone: Zone = .unknown,
        currentZone: Zone = .unknown,
        velocity: CGVector = .zero,
        confidence: Float,
        isVisible: Bool,
        lastSeenFrame: Int,
        zIndex: Int = 0,
        underlaidCardIDs: [TrackedObjectID] = [],
        recognizedLabel: String? = nil
    ) {
        self.id = id
        self.type = type
        self.center = center
        self.boundingBox = boundingBox
        self.rotation = rotation
        self.previousZone = previousZone
        self.currentZone = currentZone
        self.velocity = velocity
        self.confidence = confidence
        self.isVisible = isVisible
        self.lastSeenFrame = lastSeenFrame
        self.zIndex = zIndex
        self.underlaidCardIDs = underlaidCardIDs
        self.recognizedLabel = recognizedLabel
    }
}

public extension TrackedObject {
    /// Ready vs Exhausted, using the card's printed orientation when the
    /// card has been recognized and falling back to bounding-box shape when
    /// it hasn't.
    ///
    /// Always prefer this over `stance` where a `CardPrinting` is available.
    /// `stance` assumes portrait means upright, which holds for 96 of the
    /// 100 printings in the bundled decks and fails for every Battlefield —
    /// those are printed **landscape**, so shape alone calls them exhausted
    /// the moment they're placed and never stops.
    ///
    /// Defined here because two callers already needed it independently
    /// (durable board state and the phase auto-detector) and the second one
    /// got it wrong by reaching for `stance` — exactly the duplication
    /// CLAUDE.md warns about, where one copy silently disagrees with the
    /// other.
    func stance(knowing printing: CardPrinting?) -> CardStance {
        guard let printing else { return stance }
        return printing.isExhausted(observedBoundingBox: boundingBox) ? .exhausted : .ready
    }
}

