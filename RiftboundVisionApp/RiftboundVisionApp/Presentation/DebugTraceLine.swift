import Foundation
import RiftboundVision

/// One line of the vision log: what tracking saw, and whether it reached
/// the engine.
///
/// A flattened copy rather than the `VisionEventTrace` itself. The trace
/// carries positions, rotations and an object type the log does not show,
/// and `VisionEvent` is not `Identifiable` — `ForEach` needs an id, and the
/// object id is not one: the same tracked object produces many events.
struct DebugTraceLine: Identifiable {
    let id = UUID()
    let objectID: TrackedObjectID
    let kind: String
    /// `"Hand → Battlefield"`, or just the zone for an appearance.
    let transition: String
    let label: String?
    let confidence: Float
    /// `false` when the event never became an `ObservedTableEvent`. These
    /// are the interesting ones: dropped events are invisible in every
    /// other view, where they look identical to the camera seeing nothing.
    let wasForwarded: Bool
    let timestamp: TimeInterval

    init(_ trace: VisionEventTrace) {
        let event = trace.event
        objectID = event.objectID
        kind = Self.name(event.type)
        label = event.recognizedLabel
        confidence = event.confidence
        wasForwarded = trace.wasForwarded
        timestamp = event.timestamp

        let from = event.previousZone.map { Self.name($0) } ?? "—"
        let to = event.currentZone.map { Self.name($0) } ?? "—"
        switch event.type {
        case .objectMoved:
            transition = "\(from) → \(to)"
        case .objectAppeared:
            transition = to
        case .objectDisappeared:
            transition = from
        case .objectRotated:
            // The rotation itself, not the zone, is what changed — and a
            // rotation is how Exhaust is observed (592/593), so which way
            // it turned is the whole content of the event.
            let exhausted = event.currentRotation.map { abs($0.truncatingRemainder(dividingBy: .pi)) > 0.01 } ?? false
            transition = "\(to) · \(exhausted ? "exhausted" : "readied")"
        }
    }

    /// Camel-case raw values spaced out — `objectDisappeared` reads as
    /// "object disappeared". Cheap, and it keeps this in step with the enum
    /// automatically rather than through a switch that a new case would
    /// silently fall out of.
    private static func name<T: RawRepresentable>(_ value: T) -> String where T.RawValue == String {
        var out = ""
        for character in value.rawValue {
            if character.isUppercase, !out.isEmpty { out.append(" ") }
            // `uppercased()` can widen one character into several, so this
            // appends a String rather than forcing a `Character` back out
            // of it.
            out += out.isEmpty ? character.uppercased() : String(character)
        }
        return out
    }
}
