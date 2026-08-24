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
    /// Only *before* the identity commits. Five readings accumulate 4.5,
    /// short of the 6.0 commit threshold, so the track is still deciding
    /// and better evidence is allowed to win. Past that point it isn't —
    /// see `committedIdentityIgnoresLaterDisagreement`.
    @Test("A sustained different reading takes over while the identity is still provisional")
    func sustainedChangeWinsBeforeCommit() {
        var readings = Array(repeating: ("Crackshot Corsair", Float(0.9)), count: 5)
        readings += Array(repeating: ("Petty Officer", Float(0.95)), count: 25)

        #expect(Self.settledLabel(readings: readings) == "Petty Officer")
    }

    // MARK: - Committed identity

    /// Feeds readings for one stationary card and returns the whole track,
    /// so a test can see whether the identity settled as well as what it is.
    private static func settledTrack(readings: [(String, Float)]) -> TrackedObject? {
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
        return last?.objects.first
    }

    /// The reported bug: a card nobody touched changing into a different
    /// card. Under vote-margin-only, a long enough run of misreads always
    /// won eventually — and the periodic halving of votes meant "long
    /// enough" kept coming around. A physical card doesn't become another
    /// card, so once the identity is settled, disagreement is a misread.
    @Test("A committed identity ignores later disagreement, however sustained")
    func committedIdentityIgnoresLaterDisagreement() {
        var readings = Array(repeating: ("Annie Fiery", Float(0.9)), count: 10)
        readings += Array(repeating: ("Petty Officer", Float(0.95)), count: 60)

        #expect(Self.settledLabel(readings: readings) == "Annie Fiery")
    }

    @Test("Identity is provisional at first and committed once the evidence is one-sided")
    func commitmentIsReported() {
        let early = Self.settledTrack(readings: Array(repeating: ("Annie Fiery", Float(0.9)), count: 3))
        #expect(early?.isIdentityCommitted == false)

        let settled = Self.settledTrack(readings: Array(repeating: ("Annie Fiery", Float(0.9)), count: 10))
        #expect(settled?.isIdentityCommitted == true)
        #expect(settled?.recognizedLabel == "Annie Fiery")
    }

    /// Committing on accumulated evidence alone would lock in whichever of
    /// two confusable cards happened to lead when the counter tripped. The
    /// margin requirement means a coin flip never settles.
    @Test("Two confusable readings never commit while they're neck and neck")
    func neckAndNeckNeverCommits() {
        let readings: [(String, Float)] = (0..<30).map { index in
            (index % 2 == 0 ? "Annie Fiery" : "Annie Stubborn", Float(0.9))
        }

        #expect(Self.settledTrack(readings: readings)?.isIdentityCommitted == false)
    }

    /// Feeds a sequence of readings for one stationary card and returns the
    /// reported label after *every* poll, not just the last — so a test can
    /// assert on how often it actually changed, not only where it ended up.
    private static func reportedLabelsOverTime(readings: [(String, Float)]) -> [String?] {
        let tracker = ObjectTracker()
        let mapper = zoneMapper()
        var results: [String?] = []
        for (index, reading) in readings.enumerated() {
            let update = tracker.update(
                detections: [detection(label: reading.0, confidence: reading.1)],
                zoneMapper: mapper, frameIndex: index + 1,
                timestamp: Double(index) * 0.1,
                previousTimestamp: index == 0 ? nil : Double(index - 1) * 0.1
            )
            results.append(update.objects.first?.recognizedLabel)
        }
        return results
    }

    /// A well-established label used to lose its lead the moment a
    /// challenger's *cumulative* total edged past it by any amount at all —
    /// here, 4 solid "Annie Fiery" reads (3.6 accumulated) get overtaken by
    /// the 4th consecutive "Annie Stubborn" read (3.80) under plain
    /// argmax-of-votes, even though Annie Fiery is clearly the
    /// better-attested card. `labelSwitchMargin` requires the challenger to
    /// clear the incumbent by a decisive amount (here it never does — 4.75
    /// vs. 3.6 falls short of the 3.0 margin), so the reported name stays
    /// put.
    @Test("A narrowly-overtaking challenger doesn't displace an established label")
    func narrowOvertakeDoesNotDisplace() {
        let readings: [(String, Float)] = [
            ("Annie Fiery", 0.90), ("Annie Fiery", 0.90),
            ("Annie Fiery", 0.90), ("Annie Fiery", 0.90), ("Annie Fiery", 0.90),
            ("Annie Stubborn", 0.95), ("Annie Stubborn", 0.95),
            ("Annie Stubborn", 0.95), ("Annie Stubborn", 0.95), ("Annie Stubborn", 0.95),
        ]
        let reported = Self.reportedLabelsOverTime(readings: readings)

        #expect(reported.allSatisfy { $0 == "Annie Fiery" })
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
