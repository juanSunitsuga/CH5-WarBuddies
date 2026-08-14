import Testing
import CoreGraphics
@testable import RiftboundVision

/// The detector re-runs on every poll and its top label can wobble between
/// similar cards, so the on-screen name changed several times a second even
/// for a card lying perfectly still. A track's identity is now the label
/// with the most accumulated evidence, not whatever the last frame said.
@Suite("Label Stability")
struct LabelStabilityTests {
    private static func zoneMapper() -> ZoneMapper {
        ZoneMapper(zones: [
            BoardZone(
                type: .base,
                polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 0), CGPoint(x: 800, y: 800), CGPoint(x: 0, y: 800)],
                owner: .player1
            )
        ])
    }

    private static func detection(label: String, confidence: Float) -> Detection {
        Detection(
            type: .card,
            center: CGPoint(x: 300, y: 300),
            boundingBox: CGRect(x: 260, y: 245, width: 80, height: 110),
            rotation: 0,
            confidence: confidence,
            recognizedLabel: label
        )
    }

    /// Feeds a sequence of readings for one stationary card and returns the
    /// label the track settled on.
    private static func settledLabel(readings: [(String, Float)]) -> String? {
        let tracker = ObjectTracker()
        let mapper = zoneMapper()
        var last: TrackerUpdateResult?
        for (index, reading) in readings.enumerated() {
            last = tracker.update(
                detections: [detection(label: reading.0, confidence: reading.1)],
                zoneMapper: mapper, frameIndex: index + 1,
                timestamp: Double(index) * 0.1,
                previousTimestamp: index == 0 ? nil : Double(index - 1) * 0.1
            )
        }
        return last?.objects.first?.recognizedLabel
    }

    @Test("A single stray misread doesn't rename a confidently-tracked card")
    func strayMisreadIsOutvoted() {
        var readings = Array(repeating: ("Crackshot Corsair", Float(0.96)), count: 10)
        readings.append(("Petty Officer", 0.51))   // one bad frame
        readings.append(("Crackshot Corsair", 0.96))

        #expect(Self.settledLabel(readings: readings) == "Crackshot Corsair")
    }

    /// The label mustn't be frozen either — a genuinely different card put
    /// in the same spot has to win once the evidence is there.
    @Test("A sustained different reading eventually takes over")
    func sustainedChangeWins() {
        var readings = Array(repeating: ("Crackshot Corsair", Float(0.9)), count: 5)
        readings += Array(repeating: ("Petty Officer", Float(0.95)), count: 25)

        #expect(Self.settledLabel(readings: readings) == "Petty Officer")
    }

    /// A detector that stops recognizing for a frame — a hand partly over
    /// the art — must not blank an established identity.
    @Test("A frame with no label keeps the established identity")
    func missingLabelKeepsIdentity() {
        let tracker = ObjectTracker()
        let mapper = Self.zoneMapper()
        for frame in 1...5 {
            _ = tracker.update(
                detections: [Self.detection(label: "Sai Scout", confidence: 0.93)],
                zoneMapper: mapper, frameIndex: frame,
                timestamp: Double(frame) * 0.1, previousTimestamp: Double(frame - 1) * 0.1
            )
        }

        let unlabelled = Detection(
            type: .card,
            center: CGPoint(x: 300, y: 300),
            boundingBox: CGRect(x: 260, y: 245, width: 80, height: 110),
            rotation: 0,
            confidence: 0.4,
            recognizedLabel: nil
        )
        let result = tracker.update(
            detections: [unlabelled], zoneMapper: mapper,
            frameIndex: 6, timestamp: 0.6, previousTimestamp: 0.5
        )

        #expect(result.objects.first?.recognizedLabel == "Sai Scout")
    }
}
