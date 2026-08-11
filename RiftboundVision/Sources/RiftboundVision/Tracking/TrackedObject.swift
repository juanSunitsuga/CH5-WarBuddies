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
        self.recognizedLabel = recognizedLabel
    }
}
