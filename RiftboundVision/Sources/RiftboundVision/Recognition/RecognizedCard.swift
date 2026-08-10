import RiftboundExpertSystem

/// The output of a separate card-recognition system (per the brief: "I
/// already have / will have a separate card-recognition system" — not
/// this layer's job to build). This type just documents the shape that
/// system is expected to hand back, and the identity split it implies:
///
///   TrackedObject.id (this layer's identity: "which physical object")
///       ↕ maintained over time by `ExpertSystemAdapter.identify(objectID:as:)`
///   RecognizedCard.definitionID (card recognition's identity: "which card")
///
/// The tracker never needs to know a card's identity to do its job;
/// `ExpertSystemAdapter` is the only place the two are joined.
public struct RecognizedCard: Sendable, Equatable {
    public let objectID: TrackedObjectID
    public let definitionID: CardDefID
    public let confidence: Double

    public init(objectID: TrackedObjectID, definitionID: CardDefID, confidence: Double) {
        self.objectID = objectID
        self.definitionID = definitionID
        self.confidence = confidence
    }
}
