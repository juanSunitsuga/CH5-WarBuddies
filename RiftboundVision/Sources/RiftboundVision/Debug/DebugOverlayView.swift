import SwiftUI

/// Debug visualization state for one frame — bounding boxes, IDs, zones,
/// rotation, and the latest `VisionEvent`, per the brief's debug-mode
/// requirements. Kept as a plain value type so the tracking/detection
/// pipeline (which knows nothing about SwiftUI) can hand this to the UI
/// layer without any view-layer dependency leaking backward.
public struct DebugFrameSnapshot: Sendable {
    public let objects: [TrackedObject]
    public let latestEvent: VisionEvent?
    public let frameSize: CGSize

    public init(objects: [TrackedObject], latestEvent: VisionEvent?, frameSize: CGSize) {
        self.objects = objects
        self.latestEvent = latestEvent
        self.frameSize = frameSize
    }
}

/// Draws bounding boxes, object IDs, zones, rotation, and the latest
/// `VisionEvent` over the camera feed — the debug overlay called for in
/// the brief. Intentionally has zero Expert System / rules knowledge.
public struct DebugOverlayView: View {
    let snapshot: DebugFrameSnapshot

    public init(snapshot: DebugFrameSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(snapshot.objects, id: \.id) { object in
                boundingBox(for: object)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let event = snapshot.latestEvent {
                    eventCard(event)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func boundingBox(for object: TrackedObject) -> some View {
        let box = object.boundingBox
        Rectangle()
            .strokeBorder(boxColor(for: object), lineWidth: 2)
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            .overlay(alignment: .topLeading) {
                Text(label(for: object))
                    .font(.caption2)
                    .padding(2)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .position(x: box.minX + 4, y: box.minY - 8)
            }
    }

    /// Occluded objects (tracked but not seen this frame — see
    /// `ObjectTracker`'s occlusion tolerance) always read orange,
    /// regardless of their last-known confidence, since "occluded" is a
    /// tracking-state fact, not a detection-quality one. Visible objects
    /// are tinted red→green by `confidence` (red at 0, green at 1) so a
    /// shaky recognition is visually obvious without reading the label.
    private func boxColor(for object: TrackedObject) -> Color {
        guard object.isVisible else { return .orange }
        let clamped = Double(min(max(object.confidence, 0), 1))
        return Color(hue: clamped * 0.33, saturation: 0.9, brightness: 0.9)
    }

    private func label(for object: TrackedObject) -> String {
        let degrees = object.rotation * 180 / .pi
        // Full recognized class name when available (e.g. "Annie Fiery")
        // rather than just the coarse `.card`/`.rune` type, which reads
        // identically for every card of the same object type.
        let identity = object.recognizedLabel ?? object.type.rawValue
        return """
        #\(object.id) \(identity)
        zone: \(object.currentZone.rawValue)
        rotation: \(String(format: "%.1f", degrees))°
        confidence: \(String(format: "%.2f", object.confidence))
        """
    }

    @ViewBuilder
    private func eventCard(_ event: VisionEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VISION EVENT").font(.caption.bold())
            Text(event.type.rawValue.uppercased()).font(.caption)
            Text("Object #\(event.objectID)").font(.caption2)
            if let from = event.previousZone, let to = event.currentZone {
                Text("\(from.rawValue) → \(to.rawValue)").font(.caption2)
            }
        }
        .padding(8)
        .background(.black.opacity(0.7))
        .foregroundStyle(.white)
        .cornerRadius(6)
    }
}
