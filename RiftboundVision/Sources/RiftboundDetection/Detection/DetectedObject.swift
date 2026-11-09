import CoreGraphics

/// The vocabulary the detection layer hands upward, and the only thing the
/// tracking layer is allowed to receive from it.
///
/// These two types used to sit in `Tracking/`, next to the code that
/// consumes them, which read as though tracking owned the detector's
/// output. They belong to layer ①: a detector produces them with no
/// tracking in the build at all, and `ObjectDetecting.detect` could not be
/// declared without them.

/// What kind of physical object this is — deliberately coarse. Detection
/// answers "is this a card or a rune," not "what card is this"; exact card
/// identity is a separate concern (`Recognition/RecognizedCard.swift` in
/// `RiftboundVision`) that maps onto a tracked object after the fact.
public enum ObjectType: String, Sendable, Equatable, Codable {
    case card
    case rune
    case unknown
}

/// One frame's raw output from the detection layer — no identity yet,
/// that's what `ObjectTracker` assigns. Deliberately excludes exact card
/// identity (see `TrackedObject`'s doc comment).
public struct Detection: Sendable {
    public let type: ObjectType
    public let center: CGPoint
    public let boundingBox: CGRect
    public let rotation: CGFloat
    public let confidence: Float
    /// See `TrackedObject.recognizedLabel` — carried through unchanged by
    /// the tracker onto whichever track this detection matches.
    public let recognizedLabel: String?

    public init(type: ObjectType, center: CGPoint, boundingBox: CGRect, rotation: CGFloat, confidence: Float, recognizedLabel: String? = nil) {
        self.type = type
        self.center = center
        self.boundingBox = boundingBox
        self.rotation = rotation
        self.confidence = confidence
        self.recognizedLabel = recognizedLabel
    }
}
