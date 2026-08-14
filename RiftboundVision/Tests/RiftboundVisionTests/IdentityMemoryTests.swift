import Testing
import CoreGraphics
@testable import RiftboundVision

/// Observed on a real table: nine cards produced tracking IDs in the
/// forties, and the log showed the same physical card arriving twice under
/// two different numbers —
///
///     #36  Maddened Marauder  appeared in Champion
///     #37  Maddened Marauder  appeared in Champion
///
/// A track that timed out used to erase its identity permanently, so a card
/// the recognizer names at 94% confidence came back a stranger after a hand
/// rested over it. The tracker wasn't following anything; it was renaming
/// everything.
@Suite("Identity Memory")
struct IdentityMemoryTests {
    private static let center = CGPoint(x: 300, y: 300)

    private static func zoneMapper() -> ZoneMapper {
        ZoneMapper(zones: [
            BoardZone(
                type: .champion,
                polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 0), CGPoint(x: 800, y: 800), CGPoint(x: 0, y: 800)],
                owner: .player1
            )
        ])
    }

    private static func detection(at center: CGPoint, label: String?) -> Detection {
        Detection(
            type: .card,
            center: center,
            boundingBox: CGRect(x: center.x - 40, y: center.y - 55, width: 80, height: 110),
            rotation: 0,
            confidence: 0.94,
            recognizedLabel: label
        )
    }

    /// Runs `pollsHidden` empty polls — a hand covering the card — which is
    /// well past the 15-poll tolerance for a zone that isn't positionally
    /// stable, so the track is genuinely dropped.
    private static func trackThroughOcclusion(
        tracker: ObjectTracker,
        label: String?,
        pollsHidden: Int
    ) -> (before: TrackedObjectID?, after: TrackedObjectID?) {
        let mapper = zoneMapper()
        var frame = 0
        func poll(_ detections: [Detection]) -> TrackerUpdateResult {
            frame += 1
            return tracker.update(
                detections: detections,
                zoneMapper: mapper,
                frameIndex: frame,
                timestamp: Double(frame) * 0.35,
                previousTimestamp: frame == 1 ? nil : Double(frame - 1) * 0.35
            )
        }

        let first = poll([detection(at: center, label: label)])
        let before = first.objects.first?.id

        for _ in 0..<pollsHidden { _ = poll([]) }

        let after = poll([detection(at: center, label: label)])
        return (before, after.objects.first { $0.isVisible }?.id)
    }

    @Test("A recognized card reclaims its ID after its track times out")
    func recognizedCardReclaimsItsID() {
        let (before, after) = Self.trackThroughOcclusion(
            tracker: ObjectTracker(),
            label: "Maddened Marauder",
            pollsHidden: 20
        )
        #expect(before != nil)
        #expect(after == before, "The same card must not come back as a new number.")
    }

    /// The counterpart: with nothing to identify it by there is no
    /// principled way to know it's the same object, so a fresh ID is
    /// correct rather than a bug.
    @Test("An unrecognized object still gets a fresh ID — nothing to reclaim by")
    func unrecognizedObjectGetsFreshID() {
        let (before, after) = Self.trackThroughOcclusion(
            tracker: ObjectTracker(),
            label: nil,
            pollsHidden: 20
        )
        #expect(before != nil)
        #expect(after != before)
    }

    /// Identity memory is bounded — a card genuinely taken off the table
    /// must eventually stop claiming its old number.
    @Test("Identity memory expires")
    func identityMemoryExpires() {
        let tracker = ObjectTracker(identityMemoryFrames: 5)
        let (before, after) = Self.trackThroughOcclusion(
            tracker: tracker,
            label: "Maddened Marauder",
            pollsHidden: 40
        )
        #expect(before != nil)
        #expect(after != before)
    }

    /// Two copies of one card must not trade numbers: the nearest retired
    /// entry wins, so each reclaims the ID it had in its own spot.
    @Test("Duplicate copies reclaim their own IDs, not each other's")
    func duplicateCopiesKeepTheirOwnIDs() {
        let tracker = ObjectTracker()
        let mapper = Self.zoneMapper()
        let left = CGPoint(x: 150, y: 300)
        let right = CGPoint(x: 650, y: 300)
        var frame = 0
        func poll(_ detections: [Detection]) -> TrackerUpdateResult {
            frame += 1
            return tracker.update(
                detections: detections, zoneMapper: mapper, frameIndex: frame,
                timestamp: Double(frame) * 0.35,
                previousTimestamp: frame == 1 ? nil : Double(frame - 1) * 0.35
            )
        }

        let first = poll([
            Self.detection(at: left, label: "Order Rune"),
            Self.detection(at: right, label: "Order Rune")
        ])
        let leftID = first.objects.first { $0.center == left }?.id
        let rightID = first.objects.first { $0.center == right }?.id
        #expect(leftID != rightID)

        for _ in 0..<20 { _ = poll([]) }

        let back = poll([
            Self.detection(at: right, label: "Order Rune"),
            Self.detection(at: left, label: "Order Rune")
        ])
        #expect(back.objects.first { $0.center == left }?.id == leftID)
        #expect(back.objects.first { $0.center == right }?.id == rightID)
    }
}
